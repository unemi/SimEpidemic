#! /bin/bash
rID=admin@simepi.intlab.soka.ac.jp
rDir=SimEpidemic
cd /Users/unemi/Program/SimEpidemic
ssh -o BatchMode=yes -o ConnectTimeout=2 $rID ls > /dev/null 2>&1
if [ $? -ne 0 ]; then echo "Could not access $rID. Check your network."; exit; fi
logFile=instLog_`date +%y%m%d%H%M%S`
xcodebuild -target SimEpidemicSV archive > $logFile
if [ $? -ne 0 ]; then echo "Archive failed. Check $logFile."; exit; fi
echo "Archive succeeded."
scp /tmp/SimEpidemic.dst/usr/local/bin/simepidemic $rID:$rDir/simepidemic.new
if [ $? -ne 0 ]; then echo "scp failed."; exit; fi
echo "Binary module was copied to $rID:$rDir/."
# ssh -t $rID "cd $rDir; ./allRestart.sh"
ssh -t $rID "cd $rDir; ./restart.sh"
