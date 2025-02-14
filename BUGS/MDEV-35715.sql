CREATE TABLE t (c BIT);
INSERT INTO t VALUES (1e+19);  # Issue does not reproduce with <19

CREATE TABLE t (c DOUBLE UNSIGNED ZEROFILL DEFAULT NULL, c2 bit(1) DEFAULT NULL);
INSERT INTO t VALUES (+3E+38,+3.4E+38);

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c BIT) ENGINE=Spider;
INSERT INTO t VALUES (1e100);

CREATE TABLE t (c INT ZEROFILL,c2 CHAR CHARACTER SET 'utf8' COLLATE 'utf8_bin',c3 ENUM ('') CHARACTER SET 'latin1' COLLATE 'latin1_bin',KEY(c)) ENGINE=InnoDB;
INSERT INTO t VALUES (-1.e-2,+1,-1.e+30);

SET sql_mode='';
CREATE DEFINER=current_user FUNCTION f (i1 SET('','')) RETURNS INT CONTAINS SQL DETERMINISTIC NO SQL NO SQL RETURN CONCAT ('FUNCTION output:',i1);
SELECT f (-1.e+30);

CREATE TABLE t (c ENUM (''''));
INSERT INTO t VALUES ((1-EXP(230)));

# Requires pquery
CREATE TABLE t(c BIT KEY,c2 INT ZEROFILL,c3 NUMERIC(0,0));
INSERT INTO t VALUES((ADDDATE('1-1-1 1:1:1',0)DIV COT(-1)) * (ATAN2('uT=qiRrMC,mnssYeK(~xIxdzOIFIlSOprZ.vM+R+tF6pcB$SZ}+Po6b%=V*1olvbKG0WPr%Gk]E_Z}LQ8(XHH/Z:J[L[Ck:Ca~,l{z2dKSS}1AkF=ytn=%UM%;Hk*[bdn@@8TXmQN~Rf7T*BtFJ[(=g{wTNMfDUMMY_[C]pHhna=D6uE=;c]m9=JOued=2bhQgPBaiSA4ej}Dfn)smPBi?4iCtjp}oRmOgGCD2/]pX^1Uf4ifHYJdt9]x1Lz:OY:6Uj7QscZE)=rl[9Gb-Q1:p0ko)M+##6SGe:3qcqDtxUG]}dr1F$YtLbDlaNC=UbA=C=6Zt,vos:=I1+0aVG3ZM[w:bK3=cE*~zN6wq9kRZgR5aj*4n=(_EG)Jk,~FuKUwd/,Gsvy}V4Mb;=JIZ/CT.#cx-yDUMMYtQ/+c)sGoWs]bcki=i{O_=F=[hm=~C.s=^R^#%=jca3gK1YBRtW[=C.S$9=DiT6N;rZ@DP_2DUMMYp]{RSr,I=tBPQ:+eP[TXulDUMMYc4=5VTpL=tUZB%qZjFQ4jV2*A7RYH/l7@l7nhpqf$=Wan}e4YO=DE/_xGJzN@BhA$D,=-DX=Ux[va7@DUMMYc%.+_S)NG5Lx[FFS9QtHDl=q^WrFMwMIss~(A=bQf%],d@@T$,NUFNlDUMMY+Xl^M*Vuogpz=IUn@Vh:~.TDUMMYr[bvs@a}1xq0+yBPWU+L0r^o=8i:;{Ex3h;=T*QB~NI]AF:#?#=E,V=/QswgI/uhR2TnU1s}f=A=L2cBeO~1k=:1Ia%^Gy5XDHcFzu4+=qs/=^~Ppxt@+Q/=~V^$gM7=x((*@dw2j0OUz2;tmGl].+_$=YL{kRBgvvP#,A]UMnQ5b%6ajFTQ4xj0wRIh@MC}a1AFM@,k~d=@V9R$lx%^uyf=#.c2#1VVI3?PGzY+PtxMW%AeZTR') - LOCALTIMESTAMP),0,(MOD(0,-1) % TAN(-1)) MOD (-1 / TIME('1-1-1 1:1:1')));
