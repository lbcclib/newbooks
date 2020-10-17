# frozen_string_literal: true

ATOM_NAMESPACE = 'http://www.w3.org/2005/Atom'
DC_NAMESPACE = 'http://purl.org/dc/elements/1.1/'

require 'nokogiri'
require 'open-uri'
require 'net/http'

# This Jekyll plugin fetches data about new books from
# Evergreen and emails interested parties about the
# new books in their subject areas
class BooksFromEvergreenGenerator < Jekyll::Generator
  def generate(site)
    new_records = records_from_evergreen site.config
    site.data['books'] = new_records
  end

  private

  def records_from_evergreen(config)
    url = "https://#{config['opac_host']}"\
          '/opac/extras/browse/atom-full/item-age'\
          "/#{config['org_unit']}/1"\
          "/#{config['num_items_to_fetch']}"\
          '?status=0&status=1&status=6&status=7'
    xml = Nokogiri::XML(URI.open(url))
    xml.xpath('//atom:entry', 'atom' => ATOM_NAMESPACE).map { |entry| Book.new(entry) }
  end
end

# A new book
class Book
  def initialize(entry)
    @author = entry.at_xpath('./atom:author', 'atom' => ATOM_NAMESPACE)
    @author = @author.text if @author
    @call_number = 'cat'
    @uri = 'cat'
    @title = entry.at_xpath('./atom:title', 'atom' => ATOM_NAMESPACE).text
    @date_cataloged = 'cat'
    @shelving_location = 'cat'
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

  def has_image?
    !@cover_image.nil?
  end

  private

  def cover_url_for(isbns)
    isbn_with_image = isbns.detect { |isbn| image_exists(isbn) }
    ol_url(isbn_with_image, 'M') if isbn_with_image
    isbn_with_image ? ol_url(isbn_with_image) : 'http://placekitten.com/g/200/300'
  end

  def ol_url(isbn)
    "https://covers.openlibrary.org/b/ISBN/#{normalize_isbn(isbn)}-M.jpg?default=false"
  end

  def image_exists(isbn)
    return false if normalize_isbn(isbn).empty?
    puts normalize_isbn(isbn)

    begin
      puts "LOOKING"
      response = Net::HTTP.get_response(URI.parse(ol_url(isbn)))
      puts response
    end
    return false if response.body.include? 'not found'
    return true if %w[200 301 302].include? response.code

    false
  end

  def normalize_isbn(isbn)
    # Evergreen delivers ISBNs in the format URN:ISBN:0123456789
    isbn.text.sub 'URN:ISBN', ''
  end
end
