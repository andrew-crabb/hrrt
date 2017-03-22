# hrrt_dorecon.rb
# Transfer HRRT study and reconstruct it.

require "rsync"
require "fileutils"

RECONDIR = %w(E: recon)
SUFFIXES = %w(_EM.l64 _EM.l64.hdr _EM.hc _TX.s _TX.l64 _TX.l64.hdr)

indir = ARGV[0]
puts "Hello I am hrrt_dorecon.rb, indir is #{indir}"
(path1, path2) = File.split(indir)

recondir = File.join(RECONDIR, path2)
puts "path1 #{path1}, path2 #{path2}"
puts "recondir #{recondir}"
Dir.mkdir(recondir) unless Dir.exist?(recondir)
Dir.chdir(indir)
SUFFIXES.each do |suffix|
#	puts "rsync -tv $indir/*${suffix} $recondir/"
#	result = Rsync.run("/path/to/src", "/path/to/dest")
#	matchings = Dir.glob("#{indir}/*#{suffix}")
	matchings = Dir.glob("*#{suffix}")
#	puts "suffix #{suffix}, matchings #{matchings}"	
	if matchings.count == 1
		infile = File.join(indir, matchings[0])
		outfile = File.join(recondir, matchings[0])
		puts "suffix #{suffix}, infile #{infile}, outfile #{outfile}: #{File.file?(infile) ? 'yes' : 'no'}"	
		FileUtils.cp(infile, outfile)
	end
end
