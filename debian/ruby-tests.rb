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
  'activerecord'  => 'sqlite3:test', # FIXME SEVERAL TESTS BEING SKIPPING
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
      results["#{component}:#{task}"] = run("TESTOPTS='--seed=0' #{ruby} -S rake #{task}")
      puts 'cd -'
    end
  end
end

failed_results = results.select { |key,value| !value }
unless failed_results.empty?
  puts "Failed tests: #{failed_results.keys.join(': ')}"
end
