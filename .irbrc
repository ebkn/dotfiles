require 'readline'
IRB.conf[:USE_READLINE] = true

# completion
require 'irb/completion'

IRB.conf[:PROMPT_MODE] = :SIMPLE

# indent
IRB.conf[:AUTO_INDENT] = true

# colorize
require 'wirb'
Wirb.start
