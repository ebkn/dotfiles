Pry.config.color = true
Pry.config.auto_indent = true
Pry.config.history.should_save = false
Pry.config.prompt = proc do |obj, _nest_level_, _pry_|
  version = ''
  version << "Rails #{Rails.version}\s" if defined? Rails
  version << "\001\e[0;31m\002"
  version << "Ruby #{RUBY_VERSION}"
  version << "\001\e[0m\002"

  "#{version} #{Pry.config.prompt_name}(#{Pry.view_clip(obj)})> "
end
