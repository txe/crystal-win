{% if flag?(:windows) %}
  require "./file_utils.windows.cr"
{% else %} 
  require "./file_utils.posix.cr"
{% end %}
