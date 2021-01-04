---
layout: page
title: New books
---
<div id="filter-wrapper">
  <select id="filter" onchange="applyFilter()">
    <option id="all">All New Books</option>
    {% for department in site.data.departments %}
      <option id="{{ department.name }}">{{ department.name }}</option>
    {% endfor %}
  </select>
</div>

<div class="grid">
  {% for book in site.data.books %}
    <div class="grid-item" id="{{ book.id }}">
      <a href="{{ book.uri }}">
        <img src="{{ book.cover_image }}" alt="">
        <h2>{{ book.title }}</h2>
      </a>
      <span class="only-medium-and-larger">
        <strong>Call number:</strong>
        {{ book.call_number }}<br />

        {% if book.author %}
          <strong>Author:</strong>
          {{ book.author }}<br />
        {% endif %}
      </span>
    </div>
  {% endfor %}
</div>

<script>
  function applyFilter() {
    var dropdown = document.getElementById('filter');
    var selectedDepartment = dropdown[dropdown.selectedIndex].id;

    var gridEntries = document.getElementsByClassName('grid-item');
    for (var i = 0; i < gridEntries.length; ++i) {
      gridEntries[i].classList.remove('hidden');
    }

    if (selectedDepartment != "all") {
      var departments = {{ site.data.departments | jsonify }};
      var match = departments.find(function(department) {
        return department['name'] == selectedDepartment;
      });
      if (match) {
        for (var i = 0; i < gridEntries.length; ++i) {
          if (match['book_ids'].indexOf(gridEntries[i].id) == -1) {
            gridEntries[i].classList.add('hidden');
          }
        }
      }
    }
  }
</script>
