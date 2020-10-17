---
layout: page
title: New books
---

<div class="grid" data-masonry='{ "itemSelector": ".grid-item", "columnWidth": 200 }'>
  {% for book in site.data.books %}
    <div class="grid-item">
      <img src="{{ book.cover_image }}">
      Title: {{ book.title }}
      Call number: {{ book.call_number }}
    </div>
  {% endfor %}
</div>

