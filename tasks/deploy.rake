namespace :macro do |ns|

  task :deploy do
    macro_folder = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    plugin_folder = File.join(ENV['MINGLE_LOCATION'], 'vendor', 'plugins', 'iteration_chart')

    def install_dir(dir, target)
      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(target)
      Dir.glob(File.join(dir, '*')).reject{|name|
        ['.svn','.git'].include?(File.basename(name))
      }.each{|name|
        if (File.directory?(name))
          install_dir(name, File.join(target, File.basename(name)))
        else
          FileUtils.install(name, target)
        end
      }
    end

    install_dir(macro_folder, plugin_folder)

    puts "#{macro_folder} successfully copied over to #{plugin_folder}. Restart the Mingle server to start using the macro."
  end

end
