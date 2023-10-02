    git_token=''

    if curl_cmd="$(curl \
                        -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36' \
                        -m 10 \
                        --request GET \
                        --url "https://api.github.com/slyfox1186" \
                        --header "Authorization: Bearer ${git_token}" \
                        --header "X-GitHub-Api-Version: 2022-11-28" \
                        -sSL "https://api.github.com/repos/${github_repo}/${github_url}")"; then
