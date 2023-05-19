# PULL THE LATEST VERSIONS OF EACH PACKAGE FROM THE WEBSITE API
curl_timeout='10'
git_token=''

git_1_fn()
{
    local github_repo github_url

    # SCRAPE GITHUB WEBSITE FOR LATEST REPO VERSION
    github_repo="$1"
    github_url="$2"
    if curl_cmd="$(curl
                        -m "$curl_timeout"
                        --request GET \
                        --url "https://api.github.com/slyfox1186" \
                        --header "Authorization: Bearer $git_token" \
                        --header "X-GitHub-Api-Version: 2022-11-28"
                        -sSL https://api.github.com/repos/$github_repo/$github_url)"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name' 2>/dev/null)"
        g_ver1="$(echo "$curl_cmd" | jq -r '.[1].name' 2>/dev/null)"
        g_ver3="$(echo "$curl_cmd" | jq -r '.[3].name' 2>/dev/null)"
        g_ver="${g_ver#OpenJPEG }"
        g_ver="${g_ver#OpenSSL }"
        g_ver="${g_ver#pkgconf-}"
        g_ver="${g_ver#release-}"
        g_ver="${g_ver#lcms}"
        g_ver="${g_ver#ver-}"
        g_ver="${g_ver#PCRE2-}"
        g_ver="${g_ver#FAAC }"
        #g_ver="${g_ver%t}"
        g_ver="${g_ver#v}"
        g_ver1="${g_ver1#v}"
        g_ver3="${g_ver3#v}"
    fi
}

git_ver_fn()
{
    local v_flag v_tag url_tag

    v_url="$1"
    v_tag="$2"

    if [ -n "$3" ]; then
        v_flag="$3"
    fi

    if [ "$v_flag" = 'T' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn' gv_url='tags'
    fi

    if [ "$v_flag" = 'R' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn'; gv_url='releases'
    fi

    "$url_tag" "$v_url" "$gv_url" 2>/dev/null
}

git_ver_fn

clear
echo "$g_ver"
echo
