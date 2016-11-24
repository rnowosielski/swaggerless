require "zip"
require 'digest/sha1'

module Swaggerless

  class Packager

    def initialize(input_dir, output_file)
      @input_dir = input_dir
      @output_file = output_file
    end

    def write
      version_hash = version_hash()
      entries = Dir.entries(@input_dir) - %w(. ..)

      ::Zip::File.open("#{@output_file}_#{version_hash}.zip", ::Zip::File::CREATE) do |io|
        write_entries entries, '', io
      end
    end

    private

    def version_hash()
      files = Dir["#{@input_dir}/**/*"].reject{|f| File.directory?(f)}
      content = files.map{|f| File.read(f)}.join
      Digest::SHA1.hexdigest(content).to_s
    end

    def write_entries(entries, path, io)
      entries.each do |e|
        zip_file_path = path == '' ? e : File.join(path, e)
        disk_file_path = File.join(@input_dir, zip_file_path)


        if File.directory? disk_file_path
          recursively_deflate_directory(disk_file_path, io, zip_file_path)
        else
          put_into_archive(disk_file_path, io, zip_file_path)
        end
      end
    end

    def recursively_deflate_directory(disk_file_path, io, zip_file_path)
      io.mkdir zip_file_path
      subdir = Dir.entries(disk_file_path) - %w(. ..)
      write_entries subdir, zip_file_path, io
    end

    def put_into_archive(disk_file_path, io, zip_file_path)
      io.get_output_stream(zip_file_path) do |f|
        f.write(File.open(disk_file_path, 'rb').read)
      end
    end
  end

end