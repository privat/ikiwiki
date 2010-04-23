#!/usr/bin/perl

system <<'EOF'
#!/bin/sh
# There should be a better way to call the builded ikiwiki with the correct paths
IKIWIKI='./ikiwiki.out --set templatedir=./t/sidebar --set libdir=. ./t/sidebar /dev/null'

run() {
	command="$1"
	found="$2"
	notfound="$3"
	desc="$4"
	out=$(sh -c "$command")
	msg=""
	nb=$(( $nb + 1 ))
	echo $out | grep -E "$found" > /dev/null 2>/dev/null || {
		msg="$msg\n#     expected : $found"
	}
	echo $out | grep -E "$notfound" > /dev/null 2>/dev/null && {
		msg="$msg\n#  expected not: $notfound"
	}
	if test -z "$msg"; then
		echo "ok $nb - $desc"
	else
		echo "not ok $nb - $desc"
		echo "#          got : $out$msg"
	fi
	return 0
}

run "$IKIWIKI --render t/sidebar/main.mdwn --disable-plugin sidebar" \
	'Main' \
	'Sidebar|Banner|Notasidebar' \
	'no sidebar'
run "$IKIWIKI --render t/sidebar/main.mdwn --plugin sidebar" \
	'Sidebar.*Main' \
	'Banner|Notasidebar' \
	'simple sidebar'
run "$IKIWIKI --render t/sidebar/main.mdwn --plugin sidebar --set-yaml active_sidebars='[sidebar]'" \
	'Sidebar.*Main' \
	'Banner|Notasidebar' \
	'active_sidebars=[sidebar]'
run "$IKIWIKI --render t/sidebar/main.mdwn --plugin sidebar --set-yaml active_sidebars=''" \
	'Sidebar.*Main' \
	'Banner|Notasidebar' \
	'active_sidebars=[]'
run "$IKIWIKI --render t/sidebar/main.mdwn --plugin sidebar --set-yaml active_sidebars='[sidebar, banner]'" \
	'Sidebar.*Main.*Banner' \
	'Notasidebar' \
	'active_sidebars=[sidebar, banner]'
run "$IKIWIKI --render t/sidebar/main.mdwn --plugin sidebar --set-yaml active_sidebars='[banner]'" \
	'Main.*Banner' \
	'Sidebar|Notasidebar' \
	'active_sidebars=[banner]'
run "$IKIWIKI --render t/sidebar/main.mdwn --plugin sidebar --set-yaml active_sidebars='[banner, notasidebar]'" \
	'Main.*Banner' \
	'Sidebar|Notasidebar' \
	'active_sidebars=[banner, notasidebar]'

EOF
