version = ARGV.pop

if version.nil?
  puts "Usage: ruby install.rb version"
  exit(64)
end

%w( activesupport activemodel activerecord actionpack actionview actionmailer railties activejob ).each do |framework|
  puts "Installing #{framework}..."
  `cd #{framework} && gem build #{framework}.gemspec && gem install #{framework}-#{version}.gem --no-ri --no-rdoc && rm #{framework}-#{version}.gem`
end

puts "Installing rails..."
`gem build rails.gemspec`
`gem install rails-#{version}.gem --no-ri --no-rdoc `
`rm rails-#{version}.gem`
