# frozen_string_literal: true

ATOM_NAMESPACE = 'http://www.w3.org/2005/Atom'

require 'nokogiri'
require 'open-uri'

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
    xml.xpath('//atom:entry', 'atom' => ATOM_NAMESPACE).map { |entry| Book.new entry }
  end
end

class Book
  def initialize(_entry)
    'BOOK'
  end
end
