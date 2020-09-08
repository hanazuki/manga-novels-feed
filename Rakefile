require 'bundler/setup'
require 'sam-build-fast/rake'

SamBuildFast::Rake.define(:sam)

task :default => :build
task :build => :'sam:build'
task :clean => :'sam:clean'

task :validate do
  sh 'sam', 'validate'
end

task :deploy => :build do
  sh 'sam', 'deploy'
end
