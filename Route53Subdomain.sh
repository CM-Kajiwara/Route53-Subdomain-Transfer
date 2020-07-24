#!/bin/bash 
set -eu
WORKDIR=$(cd $(dirname $0); pwd)
function countDown() {
  start=1
  end=30
  echo "please wait $end seconds"
  while [[ $start -le $end ]]; do
    echo $(($end-$start))
    sleep 1
    start=$(($start+1))
  done
}

# 実行時に指定された引数の数、つまり変数 $# の値が 3 でなければエラー終了。
if [ $# -ne 4 ]; then
  echo "指定された引数は$#個です。" 1>&2
  echo "実行するには4個の引数が必要です。" 1>&2
  echo "$0 [TARGET Domain] [AWS CLI AccountA Profile] [SUB Domain] [AWS CLI AccountB Profile]"
  exit 1
fi

targetDomain=$1
AccountA_Profile=$2
SubDomain=$3
AccountB_Profile=$4
echo "委譲元ドメインは $targetDomain です。"
echo "指定された委譲元Profileは $AccountA_Profile です。"
echo "作成するサブドメインは $SubDomain です。"
echo "指定された委譲先Profileは $AccountB_Profile です。"
# 1.アカウントB（委譲先）でサブドメインのHosted Zoneを作成
uuid=`uuid`
createHostedZoneResult=`aws route53 create-hosted-zone --name $SubDomain --caller-reference $uuid --hosted-zone-config Comment="create command line and shell" --profile $AccountB_Profile`
createdHostedZoneId=`echo $createHostedZoneResult| jq -r  '.HostedZone.Id'`
nsRecords=`echo $createHostedZoneResult| jq -r  '[.DelegationSet.NameServers[]|{"Value":.}]'`
echo "作成したHostedZoneIdは $createdHostedZoneId です。"
echo "作成したHostedZoneのNSRecoredは $nsRecords です。"
# 確認用のレコードを作成しておきます。
cp TXTRecord_template.json TXTRecord.json
gsed -i"" -e "s/%subdomain%/$SubDomain/" $WORKDIR/TXTRecord.json
aws route53 change-resource-record-sets --hosted-zone-id $createdHostedZoneId --change-batch file://$WORKDIR/TXTRecord.json --profile ${AccountB_Profile}
# 登録したレコードが見えないことを確認します。
echo "登録したレコードが見えないことを確認します。create test のレコードが見えていなければ成功です。"
dig TXT @8.8.8.8 ${SubDomain}
read -p "Hit enter: "
# 2. 1で作成されたサブドメインのNSレコードをアカウントA（委譲元）のNSレコードに設定
cp NSRecord_template.json NSRecordTemp.json
gsed -i"" -e "s/%subdomain%/$SubDomain/" $WORKDIR/NSRecordTemp.json
cat NSRecordTemp.json | jq ".Changes[0].ResourceRecordSet.ResourceRecords |= .+${nsRecords}" > NSRecord.json
rm NSRecordTemp.json # 中間ファイルを削除
targetHostedZoneId=`aws route53 list-hosted-zones-by-name --dns-name ${targetDomain} --profile ${AccountA_Profile} | jq -r ".HostedZones[]| select(.Name == \"${targetDomain}\").Id"`
echo "同一のMFAを連続で入力するとエラーとなるため一度待機します。"
countDown
aws route53 change-resource-record-sets --hosted-zone-id $targetHostedZoneId --change-batch file://$WORKDIR/NSRecord.json --profile ${AccountA_Profile}
echo "登録したレコードを確認するために一度待機します。"
countDown
echo "登録したレコードが見えることを確認します。create test のレコードが見えていれば成功です。"
dig TXT @8.8.8.8 ${SubDomain}