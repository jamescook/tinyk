---
layout: default
title: Home
nav_order: 1
---

<div class="page-header">
<h1 class="page-title">Teek API Documentation</h1>
{% include search.html %}
</div>

Tcl/Tk interface for Ruby (8.6+ and 9.x).

## Quick Links

- [Teek::App](/api/Teek/App/) - Main entry point

## Getting Started

```ruby
require 'teek'

app = Teek::App.new
app.set_window_title('Hello Teek')
app.command(:button, '.b', text: 'Hello', command: proc { app.destroy('.') })
app.command(:pack, '.b')
app.mainloop
```

## Search

Use the search box above to find classes, modules, and methods.
