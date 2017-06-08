{% if flag?(:windows) %}
  require "./process.windows.cr"
{% else %}
  require "./process.posix.cr"
{% end %}