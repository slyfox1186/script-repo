curl_timeout='10'

git_1_fn() {
    local github_repo github_url

    github_repo="$1"
    github_url="$2"
    git_token=''

    if curl_cmd="$(curl \
                        -m 10 \
                        --request GET \
                        --url "https://api.github.com/slyfox1186" \
                        --header "Authorization: Bearer $git_token" \
                        --header "X-GitHub-Api-Version: 2022-11-28" \
                        -sSL "https://api.github.com/repos/$github_repo/$github_url")"; then
        g_url="$(echo "$curl_cmd" | jq -r '.tarball_url')"
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_deb_url="$(echo "$curl_cmd" | jq -r '.' | grep 'browser_download_url' | head -n1 | grep -Eo 'http.*b')"
        g_ver3="$(echo "$curl_cmd" | jq -r '.[3].name')"
        g_deb_ver="$g_ver%-*"
        g_url="$(echo "$curl_cmd" | jq -r '.[0].tarball_url')"
    fi

    echo "$github_repo%/*-$g_ver" >> "$ver_file_tmp"
    awk '!NF || !seen[$0]++' "$latest_txt_tmp" > "$ver_file"
}

git_2_fn() {
    videolan_repo="$1"
    videolan_url="$2"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://code.videolan.org/api/v4/projects/$videolan_repo/repository/$videolan_url")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].commit.id')"
        g_sver="$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')"
        g_ver1="$(echo "$curl_cmd" | jq -r '.[0].name')"
    fi
}

git_3_fn() {
    gitlab_repo="$1"
    gitlab_url="$2"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://gitlab.com/api/v4/projects/$gitlab_repo/repository/$gitlab_url")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"

        g_ver1="$(echo "$curl_cmd" | jq -r '.[0].commit.id')"
        g_sver1="$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')"
    fi
}

git_4_fn() {
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://gitlab.freedesktop.org/api/v4/projects/$gitlab_repo/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
    fi
}

git_5_fn() {
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL 'https://bitbucket.org/!api/2.0/repositories/multicoreware/x265_git/effective-branching-model')"; then
        g_ver="$(echo "$curl_cmd" | jq '.development.branch.target' | grep -Eo '[0-9a-z][0-9a-z]+' | sort | head -n 1)"
        g_sver="$g_ver::7"
    fi
}

git_6_fn() {
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://gitlab.gnome.org/api/v4/projects/$gitlab_repo/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
    fi
}

git_7_fn() {
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://git.archive.org/api/v4/projects/$gitlab_repo/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
    fi
}

git_ver_fn() {
    local v_flag v_tag url_tag

    v_url="$1"
    v_tag="$2"

    if [ -n "$3" ]; then
        v_flag="$3"
    fi

    if [ "$v_flag" = 'B' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn' gv_url='branches'
    elif [ "$v_flag" = 'B' ] && [  "$v_tag" = '3' ]; then
        url_tag='git_3_fn' gv_url='branches'
    fi

    if [ "$v_flag" = 'X' ] && [  "$v_tag" = '5' ]; then
        url_tag='git_5_fn'
    fi

    if [ "$v_flag" = 'T' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn' gv_url='tags'
    elif [ "$v_flag" = 'T' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn' gv_url='tags'
    elif [ "$v_flag" = 'T' ] && [  "$v_tag" = '3' ]; then
        url_tag='git_3_fn' gv_url='tags'
    fi

    if [ "$v_flag" = 'R' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn'; gv_url='releases'
    elif [ "$v_flag" = 'R' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn'; gv_url='releases'
    elif [ "$v_flag" = 'R' ] && [  "$v_tag" = '3' ]; then
        url_tag='git_3_fn' gv_url='releases'
    fi

    if [ "$v_flag" = 'L' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn'; gv_url='releases/latest'
    fi

    case "$v_tag" in
        2)          url_tag='git_2_fn';;
        3)          url_tag='git_3_fn';;
        4)          url_tag='git_4_fn';;
        5)          url_tag='git_5_fn';;
        6)          url_tag='git_6_fn';;
        7)          url_tag='git_7_fn';;
    esac

    "$url_tag" "$v_url" "$gv_url" 2>/dev/null
}

check_version() {
    github_repo="$1"
    latest_txt_tmp="$ver_file_tmp"
    latest_txt="$ver_file"

    awk '!NF || !seen[$0]++' "$latest_txt_tmp" > "$latest_txt"

        if [ -n "$check_ver" ]; then
            g_nocheck='0'
        else
            g_nocheck='1'
        fi
}

pre_check_ver() {
    github_repo="$1"
    git_ver="$2"
    git_url_type="$3"

    check_version "$github_repo"
    if [ "$g_nocheck" -eq '1' ]; then
        git_ver_fn "$github_repo" "$git_ver" "$git_url_type"
    else
    fi
}

pre_check_ver

clear
echo "$g_ver"
echo
