# OCI_GG_DEMO

# Demo After Provisioning of the Stack #

1. Go to console check Goldengate VM IP
2. Login to VM
ssh -i "/Users/shadab/Downloads/Oracle Content/Keys/mydemo_vcn.priv" -o ServerAliveInterval=30 opc@168.138.110.19

 cat ogg-credentials.json
{"username": "oggadmin", "credential": "XLl.dgWbff9asvfL"}

3. Check configuration

cd /u02/deployments/ServiceManager/etc/conf

cat deploymentRegistry.dat

4. Download Wallet Files for both ADB's using oci-cli

cd /home/opc/.oci/wallet

-- Sydney -- 

oci db autonomous-database generate-wallet \
 --autonomous-database-id ocid1.autonomousdatabase.oc1.ap-sydney-1.abzxsljrdttammj5i7en2qyav546cjjr5jvqdvqyod66r6kinqoqg4cm562a \
 --file /home/opc/.oci/wallet/Wallet_DemoSYD.zip \
 --password RAbbithole1234#_ \
  --region ap-sydney-1 \
 --profile Shadab-Migrate
 
 -- Ashburn --
 
 oci db autonomous-database generate-wallet \
 --autonomous-database-id ocid1.autonomousdatabase.oc1.iad.abuwcljtrdhi7q5htfou34qkhk53fnuooi5xwgrhljpwut2cpbggwmsb22ka \
 --file /home/opc/.oci/wallet/Wallet_DemoIAD.zip \
 --password RAbbithole1234#_ \
 --region us-ashburn-1 \
 --profile Shadab-Migrate
 
ssh -i ~/.ssh/mydemo_vcn.priv opc@168.138.110.19

scp -i ~/.ssh/mydemo_vcn.priv /home/opc/.oci/wallet/Wallet_DemoSYD.zip opc@168.138.110.19:/u02/deployments/Source/etc

scp -i ~/.ssh/mydemo_vcn.priv /home/opc/.oci/wallet/Wallet_DemoIAD.zip opc@168.138.110.19:/u02/deployments/Target/etc

ssh -i ~/.ssh/mydemo_vcn.priv opc@168.138.110.19

cd /u02/deployments/Source/etc

unzip Wallet_DemoSYD.zip

cd /u02/deployments/Target/etc

unzip Wallet_DemoIAD.zip

5. Set Wallet Location 

eg: Source

cd /u02/deployments/Source/etc

vi /u02/deployments/Source/etc/sqlnet.ora

WALLET_LOCATION = (SOURCE = (METHOD = file) (METHOD_DATA = (DIRECTORY=”/u02/deployments/Source/etc”)))
SSL_SERVER_DN_MATCH=yes

6. Set Wallet Location Target

cd /u02/deployments/Target/etc

vi /u02/deployments/Target/etc/sqlnet.ora

WALLET_LOCATION = (SOURCE = (METHOD = file) (METHOD_DATA = (DIRECTORY=”/u02/deployments/Target/etc”)))
SSL_SERVER_DN_MATCH=yes

7. — Source Setup —

a. Create Schema and Table which needs to be replicated

cd /u02/deployments/Source/etc

export ORACLE_HOME='/u01/app/client/oracle19'
export TNS_ADMIN='/u02/deployments/Source/etc'

/u01/app/client/oracle19/bin/sqlplus admin/RAbbithole1234#_@demosydney_high

create user goldengateusr identified by PassW0rd_#21 default tablespace DATA quota unlimited on DATA;
create table goldengateusr.accounts (id number primary key, name varchar2(100));
insert into goldengateusr.accounts values (1,’Shadab’);
commit;
select * from goldengateusr.accounts;

b. Unlock ggadmin user and enable supplemental log data

alter user ggadmin identified by PassW0rd_#21 account unlock;
ALTER PLUGGABLE DATABASE ADD SUPPLEMENTAL LOG DATA;
select minimal from dba_supplemental_logging;

select to_char(current_scn) from v$database;
16770256747044

c. Create extract parameter file

mkdir /u02/trails/dirdat
mkdir -p /u02/deployments/Source/etc/conf/ogg/
vi /u02/deployments/Source/etc/conf/ogg/ext1.prm

EXTRACT ext1
USERID ggadmin@demosydney_high, PASSWORD PassW0rd_#21
EXTTRAIL ./dirdat/sy
ddl include mapped
TABLE goldengateusr.*;

d. Add the extract to source
/u01/app/ogg/oracle19/bin/adminclient

CONNECT https://localhost/ deployment Source as oggadmin password XLl.dgWbff9asvfL !

ALTER CREDENTIALSTORE ADD USER ggadmin@demosydney_high PASSWORD PassW0rd_#21 alias demosydney_high

DBLOGIN USERIDALIAS demosydney_high

ADD EXTRACT ext1, INTEGRATED TRANLOG, SCN 16770256747044
REGISTER EXTRACT ext1 DATABASE
ADD EXTTRAIL ./dirdat/sy, EXTRACT ext1

START EXTRACT ext1
INFO EXTRACT ext1, DETAIL

The status should be ‘running’

e. Insert rows in source table

/* Insert another row in source table */
insert into goldengateusr.accounts values (2,’John Doe’);
insert into goldengateusr.accounts values (3,’Mary Jane’);
commit;

f. Take a datapump backup of the schema until the SCN to the internal directory ‘DATA_PUMP_DIR’

export ORACLE_HOME='/u01/app/client/oracle19'
export TNS_ADMIN='/u02/deployments/Source/etc'

/u01/app/client/oracle19/bin/expdp userid=admin/RAbbithole1234#_@demosydney_high directory=data_pump_dir dumpfile=export01.dmp logfile=export.log schemas=goldengateusr FLASHBACK_SCN=16770256747044

g. Create Bucket, Auth Token for access and DBMS_CLOUD credentials to copy export backup to Customer bucket
Create a Bucket in your tenancy called ‘datapump’ and create an Auth Token for your OCI user which has read/write permissions to this bucket

$ /u01/app/client/oracle19/bin/sqlplus admin/RAbbithole1234#_@demosydney_high 

BEGIN
DBMS_CLOUD.CREATE_CREDENTIAL(
credential_name => ‘LOAD_DATA’,
username => ‘oracleidentitycloudservice/shadab.mohammad@oracle.com‘,
password => ‘CR+R1#;4o5M[HJPgsn);’
);
END;
/

— BEGIN
— DBMS_CLOUD.drop_credential(credential_name => ‘LOAD_DATA’);
— END;
— /

BEGIN
DBMS_CLOUD.PUT_OBJECT (‘LOAD_DATA’,’ https://objectstorage.ap-sydney-1.oraclecloud.com/n/ocicpm/b/datapump/’,’DATA_PUMP_DIR’,’export01.dmp‘);
END;
/

select object_name, bytes from dbms_cloud.list_objects(‘LOAD_DATA’,’https://objectstorage.ap-sydney-1.oraclecloud.com/n/ocicpm/b/datapump/‘);

8. — Target Setup —

a. Create DBMS_CLOUD credential on target
cd /u02/deployments/Target/etc/

export ORACLE_HOME='/u01/app/client/oracle19'
export TNS_ADMIN='/u02/deployments/Target/etc/'

$ /u01/app/client/oracle19/bin/sqlplus admin/RAbbithole1234#_@demoashburn_high

BEGIN
DBMS_CLOUD.CREATE_CREDENTIAL(
credential_name => ‘LOAD_DATA’,
username => ‘oracleidentitycloudservice/shadab.mohammad@oracle.com‘,
password => ‘CR+R1#;4o5M[HJPgsn);’
);
END;
/

select object_name, bytes from dbms_cloud.list_objects(‘LOAD_DATA’,’https://objectstorage.ap-sydney-1.oraclecloud.com/n/ocicpm/b/datapump/‘);

b. Unlock ggadmin user on target and enable supplemental log data

alter user ggadmin identified by PassW0rd_#21 account unlock;
ALTER PLUGGABLE DATABASE ADD SUPPLEMENTAL LOG DATA;
select minimal from dba_supplemental_logging;

c. Import the datapump backup from customer bucket to Target ADB

$ /u01/app/client/oracle19/bin/impdp userid=admin/RAbbithole1234#_@demoashburn_high credential=LOAD_DATA schemas=goldengateusr directory=DATA_PUMP_DIR dumpfile=https://objectstorage.ap-sydney-1.oraclecloud.com/n/ocicpm/b/datapump/o/export01.dmp logfile=import.log

d. Create replicat parameter file

mkdir -p /u02/deployments/Target/etc/conf/ogg/

vi /u02/deployments/Target/etc/conf/ogg/repl1.prm

Replicat repl1
USERID ggadmin@demoashburn_high, PASSWORD PassW0rd_#21
dboptions suppresstriggers
reperror (0001, discard)
reperror (1403, discard)
map goldengateusr.*, target goldengateusr.*;

e. Create replicat in Target ADB

$ /u01/app/ogg/oracle19/bin/adminclient

CONNECT https://localhost deployment Target as oggadmin password XLl.dgWbff9asvfL !
ALTER CREDENTIALSTORE ADD USER ggadmin@demoashburn_high PASSWORD PassW0rd_#21 alias demoashburn_high
DBLOGIN USERIDALIAS demoashburn_high

ADD CHECKPOINTTABLE ggadmin.chkpt
Add Replicat repl1 exttrail ./dirdat/sy CHECKPOINTTABLE ggadmin.chkpt

Start Replicat repl1
info replicat repl1, DETAIL

Status should be ‘running’, give it a min or 2 to start

9. Now that the replication has started, insert few records in source table and you should be able to see them in target DB. Review /u02/deployments/Target/var/log/ggserr.log for any errors related to the replication

–Source–
export ORACLE_HOME='/u01/app/client/oracle19'
export TNS_ADMIN='/u02/deployments/Source/etc/'

$ /u01/app/client/oracle19/bin/sqlplus admin/RAbbithole1234#_@demosydney_high

select * from goldengateusr.accounts;

insert into goldengateusr.accounts values (4,’Foo Bar’);
insert into goldengateusr.accounts values (5,’Dummy Value’);
commit;

–Target —
export ORACLE_HOME='/u01/app/client/oracle19'
export TNS_ADMIN='/u02/deployments/Target/etc/'

$ /u01/app/client/oracle19/bin/sqlplus admin/RAbbithole1234#_@demoashburn_high

select * from goldengateusr.accounts;

We should now be able to see the new records in the Target DR Database.

10. Since we have included the DDL in the Extract, we can also create a table in Source and it will be auto-magically replicated to the Target

–Source–
create table goldengateusr.cardholder (id number primary key, cardno varchar2(30));

insert into goldengateusr.cardholder values(1,’1234-5677-9876-8765′);
commit;

–Target —
desc goldengateusr.cardholder ;
select * from goldengateusr.cardholder ; 


== Bi Directional ==

vi /u02/deployments/Target/etc/conf/ogg/ext1.prm

EXTRACT ext1
USERID ggadmin@demoashburn_high, PASSWORD PassW0rd_#21
EXTTRAIL ./dirdat/sx
ddl include mapped
TABLE goldengateusr.*;

/u01/app/ogg/oracle19/bin/adminclient

CONNECT https://localhost/ deployment Target as oggadmin password XLl.dgWbff9asvfL !

DBLOGIN USERIDALIAS demoashburn_high

ADD EXTRACT ext1, INTEGRATED TRANLOG, BEGIN NOW
REGISTER EXTRACT ext1 DATABASE
ADD EXTTRAIL ./dirdat/sx, EXTRACT ext1

START EXTRACT ext1
INFO EXTRACT ext1, DETAIL

The status should be ‘running’

vi /u02/deployments/Source/etc/conf/ogg/repl1.prm

Replicat repl1
USERID ggadmin@demosydney_high, PASSWORD PassW0rd_#21
dboptions suppresstriggers
reperror (0001, discard)
reperror (1403, discard)
map goldengateusr.*, target goldengateusr.*;

/u01/app/ogg/oracle19/bin/adminclient

CONNECT https://localhost deployment Source as oggadmin password XLl.dgWbff9asvfL !

DBLOGIN USERIDALIAS demosydney_high

ADD CHECKPOINTTABLE ggadmin.chkpt
Add Replicat repl1 exttrail ./dirdat/sx CHECKPOINTTABLE ggadmin.chkpt

Start Replicat repl1
info replicat repl1, DETAIL

-- Test by inserting transactions in target db --

export ORACLE_HOME='/u01/app/client/oracle19'
export TNS_ADMIN='/u02/deployments/Target/etc/'

/u01/app/client/oracle19/bin/sqlplus admin/RAbbithole1234#_@demoashburn_high

select * from goldengateusr.accounts;

insert into goldengateusr.accounts values (6,'Kratos Legend');
insert into goldengateusr.accounts values (7,'Achilles Reel');
commit;

export ORACLE_HOME='/u01/app/client/oracle19'
export TNS_ADMIN='/u02/deployments/Source/etc/'

/u01/app/client/oracle19/bin/sqlplus admin/RAbbithole1234#_@demosydney_high

select * from goldengateusr.accounts;

If you get error 
"Oracle GoldenGate Delivery for Oracle, repl1.prm: Aborted grouped transaction on TG8YCDUX0RLQNBP_DEMOASHBURN.GOLDENGATEUSR.ACCOUNTS, Database error 1 (OCI Error ORA-00001: unique constraint (GOLDENGATEUSR.SYS_C0021359) violated (status = 1), SQL <INSERT INTO "GOLDENGATEUSR"."ACCOUNTS" ("ID","NAME") VALUES (:a0,:a1)>)."

Then make sure the Replicat which is abending in the deployment for eg: Target has the below options added to the rep1.prm file

dboptions suppresstriggers
reperror (0001, discard)
reperror (1403, discard)

This tells the target database to skip ORA-0001 and ORA-1403 and avoid the logical conflicts. This is not a production grade way of doing this, ideally CDR scenarios should be handled by having COMPARECOLS / RESOLVECONFLICTS option, not AUTO-CDR. There are special settings you need to enable for active-active to be successful (like EXCLUDETAG), so make sure you follow the documentation, or one of the many white papers / blog sites devoted to Active-Active replication with OGG.
