"""NM2 DB-API adapter executed through MATLAB pyrunfile; returns native Python values."""
import math, re, sqlite3, urllib.parse

def imp(names):
    last=None
    for n in names:
        try:
            return __import__(n, fromlist=["*"])
        except Exception as e:
            last=e
    raise last

def uri_parts(raw):
    try:
        return urllib.parse.urlsplit(raw) if "://" in (raw or "") else None
    except Exception:
        return None

def uri_with_database(raw,database):
    u=uri_parts(raw)
    if not u:
        return raw
    path=("/"+urllib.parse.quote(str(database),safe="")) if database else ""
    return urllib.parse.urlunsplit((u.scheme,u.netloc,path,u.query,u.fragment))

def url_database(raw):
    u=uri_parts(raw)
    return urllib.parse.unquote((u.path or "").lstrip("/")) if u else ""

def conn(cfg):
    c=cfg.get("connector")
    op=cfg.get("operation")
    pw=cfg.get("password") or ""
    raw=cfg.get("url") or ""
    if c=="sqlite_file":
        return sqlite3.connect(cfg.get("file"))
    if c=="postgresql":
        m=imp(["psycopg","psycopg2"])
        kw={}
        db=cfg.get("database") or url_database(raw)
        if op=="list_databases": db="postgres"
        if cfg.get("user"):
            kw["user"]=cfg.get("user")
        if pw:
            kw["password"]=pw
        if uri_parts(raw):
            return m.connect(uri_with_database(raw,db or "postgres"), **kw)
        if raw:
            kw["host"]=raw
        if db:
            kw["dbname"]=db
        elif op=="list_databases":
            kw["dbname"]="postgres"
        return m.connect(**kw)
    if c=="mysql":
        m=imp(["pymysql","mysql.connector","MySQLdb","mariadb"])
        u=uri_parts(raw)
        kw={}
        db=cfg.get("database") or url_database(raw)
        if op=="list_databases": db=""
        if u:
            kw.update(host=u.hostname or "localhost", port=u.port or 3306)
            if u.username:
                kw["user"]=urllib.parse.unquote(u.username)
        else:
            kw.update(host=raw or "localhost")
        if db:
            kw["database"]=db
        if cfg.get("user"):
            kw["user"]=cfg.get("user")
        if pw:
            kw["password"]=pw
        return m.connect(**{k:v for k,v in kw.items() if v not in (None,"")})
    if c=="odbc_dsn":
        cs=raw
        if "=" not in cs and ";" not in cs:
            cs="DSN="+cs
        if cfg.get("user"):
            cs += ";UID=" + str(cfg.get("user"))
        if pw:
            cs += ";PWD=" + str(pw)
        return imp(["pyodbc"]).connect(cs)
    raise RuntimeError("Unsupported Python connector: %s" % c)

def lit(v):
    return "'" + str(v or "").replace("'","''") + "'"

def qident(v, quote='"'):
    text=str(v or "")
    if not text:
        raise RuntimeError("Database identifier must not be empty.")
    if quote=="[":
        return "[" + text.replace("]","]]" ) + "]"
    return quote + text.replace(quote,quote+quote) + quote

def quote_char(cn,c):
    if c=="mysql":
        return "`"
    if c in ("sqlite_file","postgresql"):
        return '"'
    if c=="odbc_dsn":
        m=imp(["pyodbc"])
        q=str(cn.getinfo(m.SQL_IDENTIFIER_QUOTE_CHAR) or "").strip()
        if not q:
            raise RuntimeError("The ODBC driver does not report an identifier quote character.")
        return q[0]
    raise RuntimeError("Identifier quoting is unsupported for connector %s" % c)

def qualified_object(cn,c,db,sch,tab):
    q=quote_char(cn,c)
    if c=="mysql":
        parts=([db] if db else [])+[tab]
    elif c=="postgresql":
        parts=([sch] if sch else [])+[tab]
    elif c=="odbc_dsn" and "." in tab:
        parts=tab.rsplit(".",1)
    else:
        parts=[tab]
    return ".".join(qident(x,q) for x in parts)

def declared_parts(native):
    text=str(native or "").strip()
    base=re.split(r"[\s(]",text,maxsplit=1)[0].lower() if text else ""
    m=re.search(r"\((\d+)\s*(?:,\s*(\d+))?\)",text)
    precision=int(m.group(1)) if m else None
    scale=int(m.group(2)) if m and m.group(2) is not None else None
    return base,precision,scale

def odbc_table_parts(tab):
    schema=None
    name=tab
    if "." in name:
        schema,name=name.rsplit(".",1)
    return schema,name

def metadata(cn,cfg):
    c=cfg.get("connector")
    op=cfg.get("operation")
    db=cfg.get("database") or url_database(cfg.get("url") or "")
    sch=cfg.get("schema") or ""
    tab=cfg.get("table") or ""
    cur=cn.cursor()
    if c=="odbc_dsn":
        if op=="list_tables":
            rows=[]
            for r in cur.tables():
                typ=str(getattr(r,"table_type","") or "").lower()
                if typ not in ("table","view"):
                    continue
                schema=str(getattr(r,"table_schem","") or "")
                name=str(getattr(r,"table_name","") or "")
                rows.append(((schema+"." if schema else "")+name, "view" if "view" in typ else "table"))
            return ["name","type"], rows
        if op=="list_columns":
            schema,name=odbc_table_parts(tab)
            object_type="table"
            for tr in cur.tables(table=name,schema=schema):
                typ=str(getattr(tr,"table_type","") or "").lower()
                if typ in ("table","view"):
                    object_type=typ
                    break
            rows=[]
            for r in cur.columns(table=name,schema=schema):
                native=str(getattr(r,"type_name","") or "")
                nullable=bool(int(getattr(r,"nullable",1) or 0))
                rows.append((str(getattr(r,"column_name","") or ""), int(getattr(r,"ordinal_position",0) or 0), native, native.lower(), int(nullable), getattr(r,"column_size",None), getattr(r,"decimal_digits",None), None, object_type))
            return ["name","ordinal","native_type","base_type","nullable","numeric_precision","numeric_scale","datetime_precision","object_type"], rows
        if op=="list_keys":
            schema,name=odbc_table_parts(tab)
            rows=[]
            for r in cur.primaryKeys(table=name,schema=schema):
                name=str(getattr(r,"pk_name","") or ""); rows.append(("primary",name or ("odbc_pk_row_%s" % int(getattr(r,"key_seq",0) or 0)),name,int(getattr(r,"key_seq",0) or 0),str(getattr(r,"column_name","") or ""),"","","",""))
            for r in cur.statistics(table=name,schema=schema,unique=True,quick=True):
                col=str(getattr(r,"column_name","") or "")
                non_unique=getattr(r,"non_unique",1)
                if not col or bool(non_unique):
                    continue
                name=str(getattr(r,"index_name","") or ""); rows.append(("unique",name or ("odbc_unique_row_%s" % int(getattr(r,"ordinal_position",0) or 0)),name,int(getattr(r,"ordinal_position",0) or 0),col,"","","",""))
            for r in cur.foreignKeys(table=name,schema=schema):
                name=str(getattr(r,"fk_name","") or ""); source=name or ("odbc_fk_row_%s" % int(getattr(r,"key_seq",0) or 0)); rows.append(("foreign",source,name,int(getattr(r,"key_seq",0) or 0),str(getattr(r,"fkcolumn_name","") or ""),str(getattr(r,"pktable_cat","") or ""),str(getattr(r,"pktable_schem","") or ""),str(getattr(r,"pktable_name","") or ""),str(getattr(r,"pkcolumn_name","") or "")))
            return ["kind","constraint_id","constraint_name","ordinal","column_name","ref_database","ref_schema","ref_table","ref_column"], rows
        raise RuntimeError("ODBC connector does not expose database/schema namespace browsing in NM2.")
    if op=="list_databases":
        if c=="mysql":
            sql="SELECT schema_name AS name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema','mysql','performance_schema','sys') ORDER BY schema_name"
        elif c=="postgresql":
            sql="SELECT datname AS name FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY datname"
        else:
            raise RuntimeError("Database namespace discovery is unsupported for connector %s" % c)
        cur.execute(sql)
        return ["name"], cur.fetchall()
    if op=="list_schemas":
        if c!="postgresql":
            raise RuntimeError("Schema discovery is only defined for PostgreSQL.")
        cur.execute("SELECT schema_name AS name FROM information_schema.schemata WHERE schema_name <> 'information_schema' AND schema_name NOT LIKE 'pg_%' ORDER BY schema_name")
        return ["name"], cur.fetchall()
    if op=="list_tables":
        if c=="sqlite_file":
            cur.execute("SELECT name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY type,name")
        elif c=="mysql":
            cur.execute("SELECT table_name AS name, CASE WHEN lower(table_type) LIKE '%view%' THEN 'view' ELSE 'table' END AS type FROM information_schema.tables WHERE table_schema="+lit(db)+" ORDER BY table_name")
        elif c=="postgresql":
            cur.execute("SELECT table_name AS name, CASE WHEN lower(table_type) LIKE '%view%' THEN 'view' ELSE 'table' END AS type FROM information_schema.tables WHERE table_schema="+lit(sch)+" ORDER BY table_name")
        else:
            raise RuntimeError("Table/view metadata discovery is unsupported for connector %s" % c)
        return ["name","type"], cur.fetchall()
    if op=="list_columns":
        if c=="sqlite_file":
            cur.execute("SELECT type FROM sqlite_master WHERE name="+lit(tab)+" AND type IN ('table','view')")
            rtype=cur.fetchone()
            object_type=str(rtype[0]).lower() if rtype else "table"
            cur.execute("PRAGMA table_info("+qident(tab)+")")
            rows=[]
            for r in cur.fetchall():
                native=str(r[2] or "")
                base,prec,scale=declared_parts(native)
                nullable=0 if bool(r[3]) or bool(r[5]) else 1
                rows.append((r[1],int(r[0])+1,native,base,nullable,prec,scale,None,object_type))
            return ["name","ordinal","native_type","base_type","nullable","numeric_precision","numeric_scale","datetime_precision","object_type"], rows
        if c=="mysql":
            sql="SELECT c.column_name, c.ordinal_position, c.column_type, c.data_type, CASE WHEN c.is_nullable='YES' THEN 1 ELSE 0 END, c.numeric_precision, c.numeric_scale, c.datetime_precision, (SELECT CASE WHEN lower(t.table_type) LIKE '%view%' THEN 'view' ELSE 'table' END FROM information_schema.tables t WHERE t.table_schema=c.table_schema AND t.table_name=c.table_name LIMIT 1) FROM information_schema.columns c WHERE c.table_schema="+lit(db)+" AND c.table_name="+lit(tab)+" ORDER BY c.ordinal_position"
        elif c=="postgresql":
            sql="SELECT c.column_name, c.ordinal_position, CASE WHEN c.data_type='USER-DEFINED' THEN c.udt_name ELSE c.data_type END, c.udt_name, CASE WHEN c.is_nullable='YES' THEN 1 ELSE 0 END, c.numeric_precision, c.numeric_scale, c.datetime_precision, (SELECT CASE WHEN lower(t.table_type) LIKE '%view%' THEN 'view' ELSE 'table' END FROM information_schema.tables t WHERE t.table_schema=c.table_schema AND t.table_name=c.table_name LIMIT 1) FROM information_schema.columns c WHERE c.table_schema="+lit(sch)+" AND c.table_name="+lit(tab)+" ORDER BY c.ordinal_position"
        else:
            raise RuntimeError("Column metadata discovery is unsupported for connector %s" % c)
        cur.execute(sql)
        return ["name","ordinal","native_type","base_type","nullable","numeric_precision","numeric_scale","datetime_precision","object_type"], cur.fetchall()
    if op=="list_keys":
        rows=[]
        if c=="sqlite_file":
            cur.execute("PRAGMA table_info("+qident(tab)+")")
            pks=sorted([(int(r[5]),str(r[1])) for r in cur.fetchall() if int(r[5] or 0)>0])
            for seq,col in pks:
                rows.append(("primary","sqlite_pk","",seq,col,"","","",""))
            cur.execute("PRAGMA index_list("+qident(tab)+")")
            indexes=cur.fetchall()
            for ir in indexes:
                if not bool(ir[2]):
                    continue
                origin=str(ir[3] or "") if len(ir)>3 else ""
                if origin.lower()=="pk":
                    continue
                idx=str(ir[1])
                cur.execute("PRAGMA index_info("+qident(idx)+")")
                for cr in cur.fetchall():
                    rows.append(("unique","sqlite_unique:"+idx,idx,int(cr[0])+1,str(cr[2]),"","","",""))
            cur.execute("PRAGMA foreign_key_list("+qident(tab)+")")
            for fr in cur.fetchall():
                rows.append(("foreign","sqlite_fk:"+str(fr[0]),"",int(fr[1])+1,str(fr[3]),"","",str(fr[2]),str(fr[4])))
            return ["kind","constraint_id","constraint_name","ordinal","column_name","ref_database","ref_schema","ref_table","ref_column"], rows
        if c=="mysql":
            sql="SELECT constraint_name, ordinal_position, column_name, referenced_table_schema, referenced_table_name, referenced_column_name FROM information_schema.key_column_usage WHERE table_schema="+lit(db)+" AND table_name="+lit(tab)+" ORDER BY constraint_name, ordinal_position"
            cur.execute(sql)
            for r in cur.fetchall():
                cname=str(r[0] or "")
                kind="primary" if cname.upper()=="PRIMARY" else ("foreign" if r[4] else "unique")
                rows.append((kind,cname,cname,int(r[1] or 0),str(r[2] or ""),str(r[3] or ""),"",str(r[4] or ""),str(r[5] or "")))
            return ["kind","constraint_id","constraint_name","ordinal","column_name","ref_database","ref_schema","ref_table","ref_column"], rows
        if c=="postgresql":
            cur.execute("SELECT constraint_name, constraint_type FROM information_schema.table_constraints WHERE table_schema="+lit(sch)+" AND table_name="+lit(tab)+" AND constraint_type IN ('PRIMARY KEY','UNIQUE','FOREIGN KEY')")
            kinds={str(r[0]):str(r[1]) for r in cur.fetchall()}
            cur.execute("SELECT constraint_name, ordinal_position, column_name, position_in_unique_constraint FROM information_schema.key_column_usage WHERE table_schema="+lit(sch)+" AND table_name="+lit(tab)+" ORDER BY constraint_name, ordinal_position")
            keyrows=cur.fetchall()
            for r in keyrows:
                cname=str(r[0] or "")
                ctype=kinds.get(cname,"")
                if ctype=="PRIMARY KEY":
                    rows.append(("primary",cname,cname,int(r[1] or 0),str(r[2] or ""),"","","",""))
                elif ctype=="UNIQUE":
                    rows.append(("unique",cname,cname,int(r[1] or 0),str(r[2] or ""),"","","",""))
                elif ctype=="FOREIGN KEY":
                    cur.execute("SELECT unique_constraint_schema, unique_constraint_name FROM information_schema.referential_constraints WHERE constraint_schema="+lit(sch)+" AND constraint_name="+lit(cname))
                    rr=cur.fetchone()
                    ref_schema=str(rr[0] or "") if rr else ""
                    ref_name=str(rr[1] or "") if rr else ""
                    cur.execute("SELECT table_name, column_name FROM information_schema.key_column_usage WHERE constraint_schema="+lit(ref_schema)+" AND constraint_name="+lit(ref_name)+" AND ordinal_position="+str(int(r[3] or r[1] or 0)))
                    kr=cur.fetchone()
                    rows.append(("foreign",cname,cname,int(r[1] or 0),str(r[2] or ""),db,ref_schema,str(kr[0] or "") if kr else "",str(kr[1] or "") if kr else ""))
            return ["kind","constraint_id","constraint_name","ordinal","column_name","ref_database","ref_schema","ref_table","ref_column"], rows
        raise RuntimeError("Key metadata discovery is unsupported for connector %s" % c)
    raise RuntimeError("Unknown metadata operation: %s" % op)

def count_rows(cn,cfg):
    c=cfg.get("connector")
    db=cfg.get("database") or url_database(cfg.get("url") or "")
    sch=cfg.get("schema") or ""
    tab=cfg.get("table") or ""
    if not tab:
        raise RuntimeError("Exact row count requires one database table/view object.")
    cur=cn.cursor()
    cur.execute("SELECT COUNT(*) FROM "+qualified_object(cn,c,db,sch,tab))
    row=cur.fetchone()
    if row is None or len(row)!=1:
        raise RuntimeError("Database COUNT(*) did not return exactly one scalar row count.")
    return ["row_count"],[(row[0],)]

def fetch_table(cn,cfg):
    c=cfg.get("connector")
    db=cfg.get("database") or url_database(cfg.get("url") or "")
    sch=cfg.get("schema") or ""
    tab=cfg.get("table") or ""
    cols=[str(x) for x in (cfg.get("columns") or [])]
    if not cols:
        raise RuntimeError("Selective table retrieval requires at least one explicit column.")
    q=quote_char(cn,c)
    sql="SELECT "+", ".join(qident(x,q) for x in cols)+" FROM "+qualified_object(cn,c,db,sch,tab)
    cur=cn.cursor()
    cur.execute(sql)
    maxrows=cfg.get("max_rows")
    rows=cur.fetchmany(int(maxrows)) if maxrows not in (None,0) else cur.fetchall()
    textcols=set(str(x) for x in (cfg.get("text_columns") or []))
    if textcols:
        indices=[i for i,name in enumerate(cols) if name in textcols]
        rows=[tuple(str(v) if i in indices and v is not None else v for i,v in enumerate(row)) for row in rows]
    return cols,rows

def fetch_query(cn,cfg):
    cur=cn.cursor()
    cur.execute(cfg.get("sql"))
    cols=[d[0] for d in cur.description] if cur.description else []
    maxrows=cfg.get("max_rows")
    rows=cur.fetchmany(int(maxrows)) if maxrows not in (None,0) else cur.fetchall()
    return cols,rows

def _as_list(value):
    if value is None:
        return []
    if isinstance(value,str):
        return [] if value=="" else [value]
    return list(value)

def run_operation(operation,connector,database_file,url,user,password,database,schema,table_name,sql,columns,text_columns,max_rows):
    cfg=dict(operation=str(operation),connector=str(connector),file=str(database_file or ""),url=str(url or ""),
        user=str(user or ""),password=str(password or ""),database=str(database or ""),schema=str(schema or ""),
        table=str(table_name or ""),sql=str(sql or ""),columns=_as_list(columns),text_columns=_as_list(text_columns),
        max_rows=None if max_rows is None or (isinstance(max_rows,float) and not math.isfinite(max_rows)) else int(max_rows))
    cn=conn(cfg)
    try:
        op=cfg.get("operation")
        if op=="describe_catalogue":
            table_cfg=dict(cfg); table_cfg["operation"]="list_tables"
            _,table_rows=metadata(cn,table_cfg)
            catalogue=[]
            for table_row in table_rows:
                object_name=str(table_row[0])
                object_type=str(table_row[1])
                object_cfg=dict(cfg); object_cfg["table"]=object_name
                column_cfg=dict(object_cfg); column_cfg["operation"]="list_columns"
                key_cfg=dict(object_cfg); key_cfg["operation"]="list_keys"
                column_cols,column_rows=metadata(cn,column_cfg)
                key_cols,key_rows=metadata(cn,key_cfg)
                _,count_data=count_rows(cn,object_cfg)
                row_count=count_data[0][0] if count_data else 0
                catalogue.append((object_name,object_type,
                    (list(column_cols),[tuple(row) for row in column_rows]),
                    (list(key_cols),[tuple(row) for row in key_rows]),row_count))
            return catalogue
        if op in ("describe_columns","describe_object"):
            column_cfg=dict(cfg); column_cfg["operation"]="list_columns"
            key_cfg=dict(cfg); key_cfg["operation"]="list_keys"
            column_cols,column_rows=metadata(cn,column_cfg)
            key_cols,key_rows=metadata(cn,key_cfg)
            description=((list(column_cols),[tuple(row) for row in column_rows]), (list(key_cols),[tuple(row) for row in key_rows]))
            if op=="describe_columns":
                return description
            _,count_data=count_rows(cn,cfg)
            row_count=count_data[0][0] if count_data else 0
            return description+(row_count,)
        if op in ("list_databases","list_schemas","list_tables","list_columns","list_keys"):
            cols,rows=metadata(cn,cfg)
        elif op=="count_rows":
            cols,rows=count_rows(cn,cfg)
        elif op=="fetch_table":
            cols,rows=fetch_table(cn,cfg)
        else:
            cols,rows=fetch_query(cn,cfg)
        return list(cols),[tuple(row) for row in rows]
    finally:
        cn.close()

if "operation" in globals():
    result=run_operation(operation,connector,database_file,url,user,password,database,schema,table_name,sql,columns,text_columns,max_rows)
