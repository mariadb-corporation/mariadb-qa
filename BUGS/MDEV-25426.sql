# Repeat until crash
# mysqld options required for replay: --log-bin 
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET @@SESSION.sql_mode='',@@GLOBAL.binlog_cache_size=256,@@GLOBAL.max_binlog_cache_size=18;
CREATE TABLE t(c BLOB,c2 INT,c3 DATE,KEY (c(1))) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t(c INT,c2 INT,c3 INT,KEY (c)) ENGINE=InnoDB;
CREATE TABLE t2(c DECIMAL(1),c2 YEAR,c3 BLOB) ENGINE=MyISAM;
SET @@GLOBAL.server_id=1;
XA START 'xid2';
INSERT INTO t2 VALUES('(QsMfc=^+N$=}t)nN8yC1wtrus_=X0q95en*rKi$-c2:8w&bh=VPpucn/&(FXO?F=c=/cwoDQ;#[:+V6N]_jw]Uk-,UF1=Ugb9q,zXOdviGa@9?xc:A','ﾟ･✿ヾ╲(｡◕‿◕｡)╱✿･ﾟ','#5i4=_@/X@^OfQgA"/bVL$p}=efKLIV{;H:p=iy0uN(=F8*[$#f)?qIbT6/]P*=@-s%WK=).,tH=A(;{cw@DcqyCiUu}E=:cA)v.c00OGc-GM,"P;o/t.Q;{ig%0)?Z$%qzLwO=),[1GDj;=(lSSmj3z{;r=r4=B+^Fdi;2K~Pq{@p46TnSNc4dIfiG]L&lW1K/:%n2lb;=+qYIUVt_w=-ae1N_Ke6~@}NWu"$6Pf{a22V"#Z$JRG1"qoNC${*S{Vt_ccvw([M+/S$xvSX}f)xSE=pJPemhngTv/Co1~:Oi:gHW9.5?G=)/*hQa=$uzgts7O;SvwI~EVtQ+-fw,]o;lShZHjG[AW5KVZiF[Ei)Cp3:~NRiPMVYjOk/UZYq4;$1jivN)BfgOHMfQquCzc0+%*tcD=_{A-a1#Qy3GMmNwc=~,$;ie[b=*{R@=#-(/%$r=O)01j=F1(V@Y$^ouupsApL~om?e~^gklTMl{("OgjRH6wSc$L~W+S;YtPG?Tdhxp;xZHJG=*%r+KnDnA)ps0_T9"7=ZP#=Ok)+t(meE.G;Wm::zuJ_0$rmH-yng*Y.}7gJYg*Vp=2+Vt~Nw5@=fEMwL_J^bOOz4&95bo)#=f"E;69x]R=qpJJt9=W[f8%FogGC=EO"vkdb6j');
INSERT INTO t SELECT * FROM t2;
SET @@SESSION.collation_connection=utf32_german2_ci;
INSERT INTO t VALUES('sk,fbr0/$g+Gn~BUkSCkx0+g=,2X=,^,cl~lcn=&[tqBOTHUTStz^j^-dn?=ud{/lR,LHtk,RN*(^4lKIDo=n^ONlBt$),=z60drS_20Js(_&A6ki?xyp;=d3a@RRyrH=eyTZoU=?uWMdp-yLas=Gg:+rH=%dH=VkfYyBw7K0/Tqa=R~dt=fW7#9=b3k_V:CA7sb98R=TtR=Y~lZ[pM["g=]JALi:$u/APg11*cp9Qcy_nT;G[Tg-c]7U{={)C=-eCia2=gQi.=:0KZnrqRJp8dUO~Rf@~$G=XU{ipdNs_]#PM+v*OdP{)"qW*lSE]=g06jc}Jaack4k,-s4iL~kHs#[Wz[WVN7X)H*I)TCIOXfax[#"gx?pRaqYQw_.:Vlm=b,+_-V3bccpQ?Plj3LiJxS]~oISRrW;G"*m27YhdHoyCl+~ZXi[v8ExpaD#=V=4huwy=Qoa#Jx={ItJo2dtT5+=Vs=35OHa:52=SI]6nWCLXzF3SPf}q"d%Un-iEzAm+v$pGh5*x0eum=H{&ws+T#KJy_Xa4Vo~*ARI,yp0lF{R("t=7#vM)?kVWz^qxrFBpH@/Nz,JG${]@dfAeV&dUdDVAI?$3)1iO,?JjxuW%@-DMt$9azV:YV=KugJkSuT?JyH)P47/vo={Wq_7(-No?Bh,9N=djSAYu&A,U^YF=J}:fEdc.mjv(*f*)o0+p[i,cjV^L1W=~h*5MwXlyKS%^=NW~qYt7a1#KA7;5.zTBAZ;*a3.f=U=&Q$:*_%nq~YDWMZcmEe:#IvV$P]:?nUVkoyn;02dR%FqL[4=9=sS6]d@$W{&8.[?{2l1Z$HFchrDr6-q{PdF9:','rn=dF;6ya3Mu#K/]jubOXhHbP)2Dg&X}PchQ^]Mqiqwsw0lF3S/Plks,+7Wi]hstBZ]fHk9olk_t}0-5N[w6J;ax0kg7DGlsxfVV9Ag~62Otvr#~P=a"@?HvLqc}(7t$b}8[dZlK1t(k"_1:GXj+97=-]8nh/]*"ILTGG"W(M=]:=JVy;Wt7slg(G$]~jh^=_^D,cd=_G?-YG:=t(xJ-em*eNW~zKdpBdLXM58=rq7*wa}=Eol9IY?o/{Od=dWR8L+X%@#Qd,hv;nIAO_=KQ1"Hk6:~pp67;reg8L)B+PRe,&z%bdD52kOl$vdLD~HBlslwno?w=s/)vP3/k9~I:&]}EGY=pk7q2O=SpgdBm*3?VwSwu]ZtBR6iX[d1wM@ea90A}A^cskt4#MsiDQ=gO+9p94dhaNN/Sd_Iig:BEW+D"L~zsKKDX9mitVZh?BsyjQ8F8E*="uK=W*wo-GNOP"(KFBS3DGCdnO,]TN-rYO2x%L-VfD,Hx}4R)K$}znE7@w=C@iMPI74kCA3[mCcvP}Zm,J(&7rckpaM6)0-{sM-;?#Kt_kTA{P2O"fsQRAr&8^NA77=?SNH;z=(:_}mMg.}=Ky#B5I^-wo+)&FFKq:c_n$dLqf"%L45KhZ8#@+zC/pZ=g=[D=v,$ha;BwPB+0QbJS.r=U&Y2lw#xMW+=G@a62~=@[;x"3rDRZ8).J*[.gcykBo=^t_rAQ=:Fk*llA=/$^Y.l}mQ;l=djh+F%8+Y{T;sqj[X9R#m-jX8=MrB4b;O3BplWAUl7-*FnY(-dMk.iG8fnE-.~v8&O^jMaKH~:OkhtXoJhtgMOZy_6#0zV0PK;x{@qjiR8:GBa+u{2p&SgI5+jwfN7^~q@9GDd0KTU}IqpFJKmB%QcEYu6gb%7uNO9XfZhkL6NLDT@+I.{tum}jS_&f=:XoyG:m"LhPw(G1ctH2sV:aI;6hfDx80QMhNI6?ownC;4iZsc5/{75NS].T60',CURRENT_TIMESTAMP(1));
DELETE FROM a3,a2 USING t AS a1 JOIN t AS a2 JOIN t2 AS a3;


# mysqld options required for replay: --log-bin 
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t(c BLOB,c2 INT,c3 DATE,KEY (c(1))) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t(c INT,c2 INT,c3 INT,KEY (c)) ENGINE=InnoDB;
CREATE TABLE t2(c INT,c2 YEAR,c3 INT) ENGINE=MyISAM;
SET @@SESSION.sql_mode='',@@GLOBAL.binlog_cache_size=10,@@GLOBAL.max_binlog_cache_size=10,@@SESSION.collation_connection=utf32_german2_ci,@@GLOBAL.server_id=1;
XA START 'a';
INSERT INTO t2 VALUES(0,0,0);
INSERT INTO t SELECT * FROM t2;
INSERT INTO t VALUES('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',0);
DELETE FROM a,b USING t AS a JOIN t2 AS b;

# mysqld options required for replay: --log-bin 
SET GLOBAL binlog_cache_size=4096, max_binlog_cache_size=4096;
CREATE TABLE t(c TEXT) ENGINE=InnoDB;
CREATE TABLE t2(a INT) ENGINE=MyISAM;
INSERT INTO t VALUES(REPEAT('a',8192));
INSERT INTO t2 VALUES (1);
START TRANSACTION;
DELETE t.*, t2.* FROM t, t2;
