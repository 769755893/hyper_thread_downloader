
git filter-branch --env-filter '
if [ $GIT_COMMIT = <$1> ];
then
    export GIT_AUTHOR_NAME="<$2>";
    export GIT_AUTHOR_EMAIL="<$3>";
fi
' -- --branches --tags
