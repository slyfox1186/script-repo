    git_token=''

    if curl_cmd="$(curl \
                        -m 10 \
                        --request GET \
                        --url "https://api.github.com/slyfox1186" \
                        --header "Authorization: Bearer ${git_token}" \
                        --header "X-GitHub-Api-Version: 2022-11-28" \
                        -sSL "https://api.github.com/repos/${github_repo}/${github_url}")"; then
