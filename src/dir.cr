{% if flag?(:windows) %}
  require "./dir.windows.cr"
{% else %} 
  require "./dir.posix.cr"
{% end %}