$env.YAZI_FILE_ONE = ($env.USERPROFILE | path join 'scoop/apps/git/current/usr/bin/file.exe')

def --env y [...args] {
	let tmp = (mktemp -t "yazi-cwd.XXXXXX")
	^yazi ...$args --cwd-file $tmp
	let cwd = (open $tmp)
	if $cwd != $env.PWD and ($cwd | path exists) {
		cd $cwd
	}
	rm -fp $tmp
}
