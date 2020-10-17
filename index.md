---
layout: page
title: New books
---

<div class="grid" data-masonry='{ "itemSelector": ".grid-item", "columnWidth": 200 }'>
  {% for book in site.data.books %}
    <div class="grid-item">
      <a href="{{ book.uri }}">
        <img src="{{ book.cover_image }}" alt="">
        <h2>{{ book.title }}</h2>
      </a>
      Call number: {{ book.call_number }}<br />
      Shelving location: {{ book.shelving_location }}<br />
      {% if book.author %}
        Author: {{ book.author }}<br />
      {% endif %}
    </div>
  {% endfor %}
</div>

