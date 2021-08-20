# Imports CMS_RUCIO_PROD.DIDS table for access time of datasets
BASE_PATH=/project/awg/cms/rucio_dids/
JDBC_URL=jdbc:oracle:thin:@cms-nrac-scan.cern.ch:10121/CMSR_CMS_NRAC.cern.ch
if [ -f /etc/secrets/rucio ]; then
  USERNAME=$(grep username </etc/secrets/rucio | awk '{print $2}')
  PASSWORD=$(grep password </etc/secrets/rucio | awk '{print $2}')
else
  echo "Unable to read Rucio credentials"
  exit 1
fi

# There should be always one folder
PREVIOUS_FOLDER=$(hadoop fs -ls $BASE_PATH | awk '{ORS=""; print $8}')
LOG_FILE=log/$(date +'%F_%H%m%S')_$(basename "$0")
TABLE=CMS_RUCIO_PROD.DIDS
TZ=UTC

/usr/hdp/sqoop/bin/sqoop import \
  -Dmapreduce.job.user.classpath.first=true \
  -Ddfs.client.socket-timeout=120000 \
  --username "$USERNAME" --password "$PASSWORD" \
  -m 10 \
  -z \
  --direct \
  --connect $JDBC_URL \
  --fetch-size 10000 \
  --as-avrodatafile \
  --target-dir "$BASE_PATH""$(date +%Y-%m-%d)" \
  --query "SELECT * FROM ${TABLE} WHERE scope='cms' AND did_type='F' AND deleted_at IS NULL AND hidden=0 AND \$CONDITIONS" \
  1>"$LOG_FILE".stdout 2>"$LOG_FILE".stderr

# change permission of HDFS area
hadoop fs -chmod -R o+rx $BASE_PATH"$(date +%Y-%m-%d)"

# Delete previous folder
hadoop fs -rmdir --ignore-fail-on-non-empty "$PREVIOUS_FOLDER"
