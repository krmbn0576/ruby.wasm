require_relative "./product"

module RubyWasm
  class BuildSource < BuildProduct
    def initialize(params, build_dir)
      @params = params
      @build_dir = build_dir
    end

    def name
      @params[:name]
    end

    def cache_key(digest)
      digest << @params[:type]
      case @params[:type]
      when "github"
        digest << @params[:rev]
      when "local"
        digest << File.mtime(@params[:src]).to_i.to_s
      else
        raise "unknown source type: #{@params[:type]}"
      end
    end

    def src_dir
      File.join(@build_dir, "checkouts", @params[:name])
    end

    def configure_file
      File.join(src_dir, "configure")
    end

    def fetch(executor)
      case @params[:type]
      when "github"
        repo_url = "https://github.com/#{@params[:repo]}.git"
        executor.mkdir_p src_dir
        executor.system "git init", chdir: src_dir
        executor.system "git remote add origin #{repo_url}", chdir: src_dir
        executor.system(
          "git fetch --depth 1 origin #{@params[:rev]}:origin/#{@params[:rev]}",
          chdir: src_dir
        ) or raise "failed to clone #{repo_url}"
        executor.system(
          "git checkout origin/#{@params[:rev]}",
          chdir: src_dir
        ) or raise "failed to checkout #{@params[:rev]}"
      when "local"
        executor.mkdir_p File.dirname(src_dir)
        executor.cp_r @params[:src], src_dir
      else
        raise "unknown source type: #{@params[:type]}"
      end
      (@params[:patches] || []).each do |patch_path|
        executor.system "patch -p1 < #{patch_path}", chdir: src_dir
      end
    end

    def build(executor)
      fetch(executor) unless File.exist?(src_dir)
      unless File.exist?(configure_file)
        Dir.chdir(src_dir) do
          executor.system "ruby tool/downloader.rb -d tool -e gnu config.guess config.sub" or
            raise "failed to download config.guess and config.sub"
          executor.system "./autogen.sh" or raise "failed to run autogen.sh"
        end
      end
    end
  end
end