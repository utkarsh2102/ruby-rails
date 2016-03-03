def run(cmd)
  puts cmd
  system 'mv lib lib.off'
  res = system(cmd)
  system 'mv lib.off lib'
  res
end

ruby = RbConfig::CONFIG['ruby_install_name']

puts
puts '[Debian Build]'
puts '========================================================================'

results = {}
{
  'actionmailer'  => 'test',
  'actionpack'    => 'test',
  'actionview'    => 'test',
  #'activejob'     => 'test', # FIXME MISSING DEPENDENCIES
  'activemodel'   => 'test',
  #'activerecord'  => 'test:sqlite3', # FIXME BROKEN
  #'activesupport' => 'test', # FIXME BROKEN
  #'railties'      => 'test', # FIXME BROKEN
}.each do |component,tasks|
  Array(tasks).each do |task|
    Dir.chdir component do
      banner = [component, task].join(' ')
      puts
      puts banner
      puts banner.gsub(/./, '-')
      puts

      puts "cd #{component}"
      results["#{component}:#{task}"] = run("#{ruby} -S rake #{task}")
      puts 'cd -'
    end
  end
end

if results.values.include?(false)
  puts "Failed tests: #{results.keys.join(': ')}"
  exit 1
end
