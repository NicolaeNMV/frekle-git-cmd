# Script files
config_file=`echo ~/.frekle_config`
projects_file=`echo ~/.frekle_projects`

# Frekle URLS
frekle_projects_url="https://zenexity.letsfreckle.com/api/projects.xml"
frekle_entries="https://zenexity.letsfreckle.com/api/entries.xml"

editor="vi"

# My git user, used to find our logs in git log
git_user=`git config --list | grep user.name | cut -f 2 -d "="`
# Git log for a particular day
git_date=$1

date_today=`date "+%Y-%m-%d"`
IFS=$'\n' # "for" seaparator
basename=`basename $0`

# Create the config file
if [ ! -e $config_file ]; then
    curl_support_ssl=`curl -V | grep " SSL "`
    if [[ ${#curl_support_ssl} -eq 0 ]]; then
        echo -e "Your curl doesn't support HTTPS, please install a version with support of ssl\nOn mac please: sudo port install curl +ssl"
        exit 1
    fi

    echo "Frekle API token is required to use this tools, you can find it on the web interface (bar on top) settings&tools->API"
    echo "Please write your frekle API token (it will be stored in $config_file)"
    echo -n "Frekle API token: "
    read frekle_api_token
    if [[ ${#frekle_api_token} -ne 31 ]]; then
        echo "Invalid API token, expected a 31 char string, got "${#frekle_api_token}", abort"
        exit 1
    fi
    touch "$config_file"
    echo "frekle_api_token=\""$frekle_api_token"\"" >> $config_file
    echo "API token has been writed to the config file ($config_file)"
    echo -n "Your frekle user (bla@email.com): "
    read frekle_user
    echo "frekle_user=\""$frekle_user"\"" >> $config_file
    echo "User has been writed to the config file ($config_file)"    
fi

# Load config file
source $config_file

if [[ ${#git_user} -eq 0 ]]; then
    echo "Cannot get your git user, are you in a git repository? cd to a git repository"
    exit 1
fi
git_url=`git remote show origin | grep "Fetch URL" | cut -d ":" -f 2-100`
if [[ ${#git_url} -eq 0 ]]; then
    echo "fatal: Not a git repository"
    exit 1
fi
git_url_md5=`echo $git_url | md5`
eval frekle_project=\$frekle_git2proj_${git_url_md5}_name
eval frekle_project_id=\$frekle_git2proj_${git_url_md5}_id
if [[ ${#frekle_project} -eq 0 ]]; then
    echo "Here is the list of projects....."
    curl --silent -H "X-FreckleToken:$frekle_api_token" $frekle_projects_url > $projects_file
    if [[ `wc -l $projects_file` -eq 0 ]]; then
        echo "Cannot get the project list, verify that your frekle api token is: "$frekle_api_token
    fi
    line=1
    cat $projects_file | grep "<name>" | sed 's/.*<name>\(.*\)<\/name>.*/\1/g' | while read N; do echo "$line $N"; line=$((line+1)); done
    lines=`grep "<name>"  $projects_file | wc -l | awk '{print $1}'`
    echo "Current repository is not assigned to any Frekle project, please "
    echo -n "Type the number of the project you want the repository git_url to be associated with (1-${lines}): "
    read frekle_projecti
    frekle_project=`cat $projects_file | grep "<name>" | sed 's/.*<name>\(.*\)<\/name>.*/\1/g' | sed -n ${frekle_projecti}p`
    frekle_project_id=`cat $projects_file | grep "<id type" | sed 's/.*<id type=\"integer\">\(.*\)<\/id>.*/\1/g' | sed -n ${frekle_projecti}p`
    echo $frekle_project_int
    frekle_project=$frekle_project
    echo "# repository $git_url " >> $config_file
    echo "frekle_git2proj_${git_url_md5}_id=\"$frekle_project_id\"" >> $config_file
    echo "frekle_git2proj_${git_url_md5}_name=\"$frekle_project\"" >> $config_file
fi

source $config_file

git_commit_messages=""

if [[ ${#1} -eq 0 ]]; then
    git_date=`date "+$date_today 00:00:00"`
fi
for L in `git log --author="$git_user" --since="$git_date" --pretty=format:'%s%n'`; do
    if [[ ${#L} -eq 0 ]]; then
        continue
    fi
    git_commit_messages=$git_commit_messages"\"$L\" and "
done

git_commit_messages=${git_commit_messages: 0: ${#git_commit_messages}-4} # remove last 4 characters

git_logs_30d=`git log --author="$git_user" --since="30 days ago" --pretty=format:'%cd %s' --date=short`

if [[ ${#git_commit_messages} -eq 0 ]]; then
    echo "Logs not found since: "$git_date
    echo "Please provide a date, format year-month-day ex. ./"$basename" $date_today"
    echo "Your git log since 30 days"
    echo "$git_logs_30d"
    exit
fi

TMPFILE=`mktemp /tmp/${basename}.XXXXXX` || exit 1
TMPFILE_DATE_REFERENCE=`mktemp /tmp/${basename}.XXXXXX` || exit 1 # Used as a tag in time to know if TMPFILE was modified
echo "# new entry to frekle Project: $frekle_project" > $TMPFILE
date "+date: %Y-%m-%d" >> $TMPFILE
echo "hours: 8h00" >> $TMPFILE
echo "description: =developpement, !"$git_commit_messages >> $TMPFILE
echo "# your last commits in 30 days" >> $TMPFILE

for L in $git_logs_30d; do
    echo "#"$L >> $TMPFILE
done;

$editor $TMPFILE

if ! [[ $TMPFILE -nt $TMPFILE_DATE_REFERENCE ]]; then
    echo "No changes detected. Aborting save."
    exit 1
fi;

hours=`cat $TMPFILE | grep "^hours:" | sed s/^hours://`
date=`cat $TMPFILE | grep "^date:" | sed s/^date://`
description=`cat $TMPFILE | grep "^description:" | sed s/^description:\//`

XMLFILE=`mktemp /tmp/${basename}.XXXXXX` || exit 1

echo '<?xml version="1.0" encoding="UTF-8"?>' > $XMLFILE
echo '<entry>' >> $XMLFILE
echo '  <minutes>'${hours}'</minutes>' >> $XMLFILE
echo '  <user>'${frekle_user}'</user>' >> $XMLFILE
echo '  <project-id type="integer">'${frekle_project_id}'</project-id>' >> $XMLFILE
echo '  <description>'${description}'</description>' >> $XMLFILE
echo '  <date>'${date}'</date>' >> $XMLFILE
echo '</entry>' >> $XMLFILE

echo "Sending the new entry.."

header=`curl -i -d @$XMLFILE -H "Content-type: text/xml" -H "X-FreckleToken:${frekle_api_token}" -s $frekle_entries | grep "HTTP/"`

if [[ `echo $header | cut -d " " -f 3` == Created* ]]; then
    echo "The entry has been created"
else
    echo "Error: $header"
fi