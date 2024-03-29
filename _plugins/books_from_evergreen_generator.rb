# frozen_string_literal: true

ATOM_NAMESPACE = 'http://www.w3.org/2005/Atom'
DC_NAMESPACE = 'http://purl.org/dc/elements/1.1/'
HOLDINGS_NAMESPACE = 'http://open-ils.org/spec/holdings/v1'

require 'dotenv/load'
require 'call_number_ranges'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'mail'
require 'rmagick'
require 'openlibrary/covers'

# This Jekyll plugin fetches data about new books from
# Evergreen and emails interested parties about the
# new books in their subject areas
class BooksFromEvergreenGenerator < Jekyll::Generator
  def generate(site)
    configure_mail site.config
    new_records = records_from_evergreen site.config
    site.data['books'] = new_records
    generate_montage site.data['books'], site.config['plugins_dir']
    site.data['departments'] = site.config['departments']
                                   .map { |department| Department.new department, site.config, site.data['books'] }
                                   .select(&:enough_books?)
    site.data['departments'].each(&:send_email)
  end

  private

  def records_from_evergreen(config)
    url = "https://#{config['opac_host']}"\
          '/opac/extras/browse/atom-full/item-age'\
          "/#{config['org_unit']}/1"\
          "/#{config['num_items_to_fetch']}"\
          '?status=0&status=1&status=6&status=7'\
          '&copyLocation=224&copyLocation=456&copyLocation=472'
    xml = Nokogiri::XML(URI.open(url))
    xml.xpath('//atom:entry', 'atom' => ATOM_NAMESPACE)
       .map { |entry| Book.new(entry) }
       .select(&:cover_image) # we only want books with cover images
  end

  def configure_mail(config)
    Mail.defaults do
      delivery_method :smtp,
                      address: config['smtp_server'],
                      port: config['smtp_port'],
                      user_name: ENV['SENDER_EMAIL'],
                      password: ENV['SENDER_PASSWORD'],
                      authentication: 'plain',
                      enable_starttls_auto: true
    end
  end

  def generate_montage(books, dir)
    selected_books = books.sample 6
    list = Magick::ImageList.new
    selected_books.each { |book| list.from_blob(URI.open(book.cover_image).read) }
    montaged_images = list.montage do |image|
      image.tile = '1x3', image.background_color = '#FDB913', self.geometry = '1080x1080+10+5'
    end
    montaged_images.write "#{dir}/instagram.png"
    send_instagram_email(selected_books, dir)
  end

  def send_instagram_email(books, dir)
    template = Liquid::Template.parse File.read "#{dir}/instagram_post.txt"
    mail = Mail.new "To: #{ENV['INSTAGRAM_POSTER_EMAIL']}\r\n"\
                    "From: libref@linnbenton.edu\r\n"\
                    "Subject: New books instagram post\r\n"\
                    "\r\n"\
                    "#{template.render('books' => books.map(&:title))}"
    mail.add_file "#{dir}/instagram.png"
    mail.deliver!
  end
end

# A new book
class Book
  attr_reader :call_number, :cover_image, :id, :title

  def initialize(entry)
    @author = entry.at_xpath('./atom:author', 'atom' => ATOM_NAMESPACE)
    @author = @author.text if @author

    @call_number = entry.at_xpath(
      './holdings:holdings/holdings:volumes/holdings:volume/@label',
      'holdings' => HOLDINGS_NAMESPACE
    ).text

    @uri = catalog_url_for entry.at_xpath('./atom:id', 'atom' => ATOM_NAMESPACE).text[/\d+/]
    @title = entry.at_xpath('./atom:title', 'atom' => ATOM_NAMESPACE).text
    @id = entry.at_xpath('./atom:id', 'atom' => ATOM_NAMESPACE).text.gsub(':', '-')

    @date_cataloged = entry.at_xpath('./atom:updated', 'atom' => ATOM_NAMESPACE)
    @date_cataloged = @date_cataloged if @date_cataloged

    @shelving_location = entry.at_xpath(
      './holdings:holdings/holdings:volumes/holdings:volume/holdings:copies/holdings:copy/holdings:location',
      'holdings' => HOLDINGS_NAMESPACE
    )
    @shelving_location = @shelving_location.text if @shelving_location

    @cover_image = cover_url_for entry.xpath('./dc:identifier[text()[contains(.,"URN:ISBN")]]', 'dc' => DC_NAMESPACE)
  end

  def to_liquid
    {
      'author' => @author,
      'call_number' => @call_number,
      'id' => @id,
      'uri' => @uri,
      'title' => @title,
      'date_cataloged' => @date_cataloged,
      'shelving_location' => @shelving_location,
      'cover_image' => @cover_image
    }
  end

  private

  def cover_url_for(isbns)
    image = Openlibrary::Covers::Image.new(isbns.map { |isbn| normalize_isbn(isbn) })
    image.url
  end

  def catalog_url_for(id)
    findit_url = "https://libfind.linnbenton.edu:4430/catalog/#{id}"
    evergreen_url = "https://libcat.linnbenton.edu/eg/opac/record/#{id}"
    findit_has(id) ? findit_url : evergreen_url
  end

  def findit_has(id)
    response = nil
    begin
      Net::HTTP.start('libfind.linnbenton.edu', 80) do |http|
        response = http.head "/catalog/#{id}"
      end
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, SocketError
      return false
    end
    response.code != '404'
  end

  def normalize_isbn(isbn)
    # Evergreen delivers ISBNs in the format URN:ISBN:0123456789
    isbn.text[/[X0-9]{10,13}/]
  end
end

# An LBCC department
class Department
  def initialize(department_config, site_config, books)
    @name = department_config['name']
    @emails = ENV[department_config['emails']]
    @discipline = department_config['discipline']
    @site_config = site_config
    @books_of_interest = books.select { |book| interested_in? book }
  end

  def send_email
    mail = Mail.new "To: #{@emails}\r\n"\
      "From: libref@linnbenton.edu\r\n"\
      'Subject: New books at the LBCC Library'
    mail.text_part = text_contents
    mail.html_part = html_contents
    mail.deliver!
  end

  def to_liquid
    {
      'name' => @name,
      'book_ids' => @books_of_interest.map(&:id)
    }
  end

  def enough_books?
    @books_of_interest.count >= @site_config['min_items_per_email']
  end

  private

  def interested_in?(book)
    CallNumberRanges::CallNumber.disciplines(book.call_number).include? @discipline
  end

  def text_contents
    contents = render_using_template 'email_template.txt'
    text_part = Mail::Part.new
    text_part.body = contents
    text_part
  end

  def html_contents
    contents = render_using_template 'email_template.html'
    html_part = Mail::Part.new { content_type 'text/html; charset=UTF-8' }
    html_part.body = contents
    html_part
  end

  def render_using_template(template_file_name)
    template = Liquid::Template.parse File.read "#{@site_config['plugins_dir']}/#{template_file_name}"
    template.render(
      'department_name' => @name,
      'books_of_interest' => @books_of_interest.first(@site_config['max_items_per_email']),
      'site_url' => @site_config['url']
    )
  end
end
