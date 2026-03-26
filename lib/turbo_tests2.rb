# For technical reasons, if we move to Zeitwerk, this cannot be require_relative.
#   See: https://github.com/fxn/zeitwerk#for_gem_extension
# But we will use require_relative to avoid the risk of it loading the old turbo_tests gem.
# Bottom-line: Do not use Zeitwerk in this gem.
# Hook for other libraries to load this library (e.g. via bundler)
require_relative 'turbo_tests'
