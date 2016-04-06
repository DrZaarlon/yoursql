#!/bin/bash

# bring back schema for table
# extract the non-primary keys
# generate string to drop keys
# generate string to add keys
# select count of tuples
# drop keys
# optimize table
# re-add keys
# select count of tuples
# compare pre and post tuple count

host="localhost"
db=""
tb=""
v=1

while getopts 'h:d:t:v' flag
do
  case ${flag} in
   'h') host=${OPTARG};;
   'd') db=${OPTARG};;
   't') tb=${OPTARG};;
   'v') v=0;;
  esac
done

USG="Usage: $0 [-h <host>] -d <db> -t <tb>"

if [[ "x${db}" == "x" || "x${tb}" == "x" ]]
then
  echo "${USG}"
  exit 1
fi

function vprint(){
 if [[ ${v} -eq 0 ]]
 then
  echo "$1"
 fi
}

mysql_comm="mysql -h ${host} ${db}"
mysql_tbl_comm="${mysql_comm} -nt"
mysql_txt_comm="${mysql_comm} -s"

str_showcr="show create table ${tb}"
str_alter="alter table ${tb} "
str_getcnt="select sum(1) from ${tb}"
str_opttab="optimize table ${tb}"

str_showsize="select table_name, (data_length+index_length+data_free)/(1024*1024*1024) as 'total_gb', data_length / (1024*1024) as 'data_mb', index_length / (1024 * 1024 ) as 'index_mb', data_free / (1024 * 1024) as 'free_mb' from information_schema.tables where table_schema = '${db}' and table_name = '${tb}'"

#get schema
tb_sch=$( ${mysql_tbl_comm} -e "${str_showcr}" )

echo ${tb_sch} | grep 'ENGINE=InnoDB' >/dev/null 2>&1
if [[ $? -ne 0 ]]
then
 echo "This Table Is Not InnoDB format"
 exit 9
fi

# bring back keys for tb in db
keys=$( echo "${tb_sch}" | grep -e 'KEY `' -e PRIMARY )

echo -e "\nORIG KEYS: ${keys}\n"

keys=$( echo "${keys}" | grep -v -e 'PRIMARY KEY' )

# generate string to drop keys
dropstr=$( echo "${keys}" | grep -o 'KEY `.*` ' | sed -e 's/KEY/, DROP KEY/g' )
dropstr=${dropstr#,}


# generate string to add keys
addstr=$( echo "${keys}" | sed -e 's/\(.*\) KEY `/ADD \1 KEY `/g' )

#echo ${dropstr}
#echo ${addstr}


exec 2>&1
time {

 # select count of tuples
 pre_count=$( ${mysql_txt_comm} -e "${str_getcnt}" )

 #show size
 ${mysql_tbl_comm} -e "${str_showsize}"

 # drop keys
 ${mysql_txt_comm} -e "${str_alter} ${dropstr}"

 # optimize table
 ${mysql_tbl_comm} -e "${str_opttab}"

 # re-add keys
 time ${mysql_txt_comm} -e "${str_alter} ${addstr}"

 ${mysql_tbl_comm} -e "${str_showsize}"

 ${mysql_txt_comm} -Nse "${str_showcr}" | sed -e 's|\\n|\n|g'

 # select count of tuples
 post_count=$( ${mysql_txt_comm} -e "${str_getcnt}" )

}

# compare pre and post tuple count
if [[ ${pre_count} -ne ${post_count} ]]
then
 echo "The Counts Changed During The Operation [${pre_count} != ${post_count}]"
else
 echo "PRE,POST: ${pre_count},${post_count}"
fi

exit 0

