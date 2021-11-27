#!/bin/bash


read -r -d '' usage <<-docEnd
This enables search for docker tags in public docker repositories

Usage $0 -r <reponame>  [options]

Options
        -a		: display all tags at once instead of page_size per iteration
        -m num		: max number of tags to display at once defaults to 100
        -r reponame	: the repository to search for tags
        --name		: filter by name of a tag
docEnd

debug() {
	[ ! -z "$DOCKER_SEARCH_LOG" ] && [ ! -f "$DOCKER_SEARCH_LOG" ] && touch "$DOCKER_SEARCH_LOG"
	[ ! -z "$DOCKER_SEARCH_LOG" ] && (echo "$(date +%FT%T) $@") >> $DOCKER_SEARCH_LOG
	return 0 
}


loader() {
	local pid=$1 
	local spin='-\|/'
	local i=0
	while kill -0 $pid 2>/dev/null
	do
		i=$(( (i+1) %4 ))
		printf "\r${spin:$i:1}"
		sleep 0.1
	done
	echo -ne "\r\033[2k"
}

checkParam() {
	[ ! -z "$1" ] && (debug "value $1 found" && return 0) || (debug "value not found" && echo "$usage" && exit 0)
}

get_all=0
repo=""
page=1
page_size=100
name_filter=""
response=""

tags() {
	local url="$base_url?page=${page}&page_size=${page_size}$(test -z "$name_filter" || echo "&name=$name_filter")"
	debug "calling url $url"
	echo "$(curl -s "$url")"
}

getTags() {
	debug "extracting tags"
	printf '%s\n' $(tags | jq -r '.results[].name')
}

[ $# -eq 0 ] && echo "$usage" && exit 0

while test $# -ge 0; do
	debug "looking @ $1"
	case "$1" in
		-m) 
			shift
			checkParam $1
			page_size=$1	
			debug "page size set to $page_size"
			;;
		-r) 
			shift
			checkParam $1	
			repo=$1
			debug "repo name set to $repo"
			;;
		--name)
		       	shift
			checkParam $1
			name_filter=$1
			debug "name filter set to $name_filter"
			;;
		-a) get_all=1;;
		*)
			debug "checking repo value"
			checkParam $repo
			base_url="https://hub.docker.com/v2/repositories/library/${repo}/tags/"
		
			debug "searching for $repo"
			tags > tags.tmp &
			loader $!
			response=$(cat tags.tmp)

			total_tag_count=$(jq -r ".count" <<< $response)
			tags=($(echo "$response" | jq -r '.results[].name'))
			rm tags.tmp

			page_count=$(((${total_tag_count}+${page_size}-1)/$page_size))
			debug "total page count $page_count"
			debug "total tag count $total_tag_count"

			([ -z "$total_tag_count" ] || [ $total_tag_count -eq 0 ]) && exit 0

			[ $get_all -eq 0 ] && (printf '%s\n' "${tags[@]}")
			for page in $(seq 2 $page_count); do
				if [ $get_all -eq 0 ]; then
					echo -en "\rremaining $((${page_count}-${page})) pages... continue? [press enter to continue]"
					read -r
					echo -en "\033\033[1A\033[2K"
				fi
				getTags > tags.tmp &
				loader $!			
				echo -ne "\033\033[1A"
				newtags=($(cat tags.tmp))
				debug "new tags size ${#newtags[@]}"
				rm tags.tmp
				if [ $get_all -eq 0 ]; then
				       	printf '%s\n' "${newtags[@]}"
					echo -ne "\033\033[1A"
				fi
				debug "tags length ${#tags[@]}"
				tags+=("${newtags[@]}")
				debug "tags length after ${#tags[@]}"
				echo 
			done
			[ $get_all -eq 1 ] && printf '%s\n' "${tags[@]}" | more
			;;
	esac
	shift
done
