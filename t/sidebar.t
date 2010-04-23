#!/usr/bin/perl

system <<'EOF'
#!/bin/sh
# There should be a better way to call the builded ikiwiki with the correct paths
cd t 2>/dev/null
cd ..

LIBPERL=".:$LIBPERL"
export LIBPERL

run() {
	page="$1"
	command="$2"
	found="$3"
	notfound="$4"
	desc="$5"
	rm -rf t/sidebar.out 2> /dev/null
	fullcommand="./ikiwiki.out --rebuild --set templatedir=t/sidebar --set underlaydir=t/sidebar --set usedirs=0 $command t/sidebar t/sidebar.out"
	sh -c "$fullcommand"
	out="t/sidebar.out/$page.html"
	msg=""
	nb=$(( $nb + 1 ))
	for x in $found; do
		grep -E "$x" "$out" > /dev/null 2>/dev/null || {
			msg="$msg\n#     expected : $x"
		}
	done
	for x in $notfound; do
		grep -E "$x" "$out" > /dev/null 2>/dev/null && {
			msg="$msg\n#  expected not: $x"
		}
	done
	if test -z "$msg"; then
		echo "ok $nb - $desc"
	else
		echo $fullcommand
		echo "not ok $nb - $desc"
		echo "#          got : "
		cat "$out"
		echo "$msg"
	fi
	return 0
}

echo "1..7"
run main "--disable-plugin sidebar" \
	'Main' \
	'Sidebar Banner Notasidebar' \
	'no sidebar'
run main "--plugin sidebar" \
	'Sidebar Main' \
	'Banner Notasidebar' \
	'simple sidebar'
run main "--plugin sidebar --set-yaml active_sidebars='[sidebar]'" \
	'Sidebar Main' \
	'Banner Notasidebar' \
	'active_sidebars=[sidebar]'
run main "--plugin sidebar --set-yaml active_sidebars=''" \
	'Sidebar Main' \
	'Banner Notasidebar' \
	'active_sidebars=[]'
run main "--plugin sidebar --set-yaml active_sidebars='[sidebar, banner]'" \
	'Sidebar Main Banner' \
	'Notasidebar' \
	'active_sidebars=[sidebar, banner]'
run main "--plugin sidebar --set-yaml active_sidebars='[banner]'" \
	'Main Banner' \
	'Sidebar Notasidebar' \
	'active_sidebars=[banner]'
run main "--plugin sidebar --set-yaml active_sidebars='[banner, notasidebar]'" \
	'Main Banner' \
	'Sidebar Notasidebar' \
	'active_sidebars=[banner, notasidebar]'
EOF
