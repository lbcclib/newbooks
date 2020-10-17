# frozen_string_literal: true

ATOM_NAMESPACE = 'http://www.w3.org/2005/Atom'
DC_NAMESPACE = 'http://purl.org/dc/elements/1.1/'
HOLDINGS_NAMESPACE = 'http://open-ils.org/spec/holdings/v1'

require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'mail'

# This Jekyll plugin fetches data about new books from
# Evergreen and emails interested parties about the
# new books in their subject areas
class BooksFromEvergreenGenerator < Jekyll::Generator
  def generate(site)
    new_records = records_from_evergreen site.config
    site.data['books'] = new_records
    configure_mail site.config
    site.config['departments']
        .map { |department| Department.new department, site.config }
        .each { |department| department.email_about site.data['books'] }
  end

  private

  def records_from_evergreen(config)
    url = "https://#{config['opac_host']}"\
          '/opac/extras/browse/atom-full/item-age'\
          "/#{config['org_unit']}/1"\
          "/#{config['num_items_to_fetch']}"\
          '?status=0&status=1&status=6&status=7'
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
                      user_name: config['email_sender'],
                      password: config['email_password'],
                      authentication: 'plain',
                      enable_starttls_auto: true
    end
  end
end

# A new book
class Book
  attr_reader :call_number, :cover_image

  def initialize(entry)
    @author = entry.at_xpath('./atom:author', 'atom' => ATOM_NAMESPACE)
    @author = @author.text if @author

    @call_number = entry.at_xpath(
      './holdings:holdings/holdings:volumes/holdings:volume/@label',
      'holdings' => HOLDINGS_NAMESPACE
    ).text

    @uri = 'https://libfind.linnbenton.edu:4430/catalog/'\
           "#{entry.at_xpath('./atom:id', 'atom' => ATOM_NAMESPACE).text[/\d+/]}"
    @title = entry.at_xpath('./atom:title', 'atom' => ATOM_NAMESPACE).text

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
      'uri' => @uri,
      'title' => @title,
      'date_cataloged' => @date_cataloged,
      'shelving_location' => @shelving_location,
      'cover_image' => @cover_image
    }
  end

  private

  def cover_url_for(isbns)
    isbn_with_image = isbns.detect { |isbn| image_exists(isbn) }
    ol_url(isbn_with_image) if isbn_with_image
    isbn_with_image ? ol_url(isbn_with_image) : nil
  end

  def ol_url(isbn)
    "https://covers.openlibrary.org/b/ISBN/#{normalize_isbn(isbn)}-M.jpg?default=false"
  end

  def image_exists(isbn)
    return false if normalize_isbn(isbn).nil?

    begin
      response = Net::HTTP.get_response(URI.parse(ol_url(isbn)))
    end
    return false if response.body.include? 'not found'
    return true if %w[200 301 302].include? response.code

    false
  end

  def normalize_isbn(isbn)
    # Evergreen delivers ISBNs in the format URN:ISBN:0123456789
    isbn.text[/[X0-9]{10,13}/]
  end
end

# An LBCC department
class Department
  def initialize(department_config, site_config)
    @name = department_config['name']
    @emails = department_config['emails']
    @regex = department_config['regex']
    @site_config = site_config
  end

  def email_about(books)
    @books_of_interest = books.select { |book| interested_in? book }
    send_email if enough_books?
  end

  private

  def interested_in?(book)
    book.call_number.match? @regex
  end

  def enough_books?
    @books_of_interest.count >= @site_config['min_items_per_email']
  end

  def send_email
    mail = Mail.new "To: #{@emails.join(', ')}\r\n"\
                    "From: libref@linnbenton.edu\r\n"\
                    'Subject: New books at the LBCC Library'
    mail.text_part = text_contents
    mail.html_part = html_contents
    mail.deliver!
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
