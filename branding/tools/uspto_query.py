import json,sys,subprocess
def q(qs,size=40):
    body={"query":{"bool":{"must":[{"query_string":{"query":qs,"default_operator":"AND","fields":["wordmark","wordmarkPseudoText"]}}]}},"size":size}
    r=subprocess.run(["curl","-s","--max-time","40","-X","POST","https://tmsearch.uspto.gov/prod-stage-v1-0-0/tmsearch","-H","Content-Type: application/json","-H","Origin: https://tmsearch.uspto.gov","-H","Referer: https://tmsearch.uspto.gov/search/search-results","-H","User-Agent: Mozilla/5.0","-d",json.dumps(body)],capture_output=True,text=True).stdout
    return json.loads(r)
if __name__=="__main__" and sys.argv[1]=="keys":
    d=q("oath",1);h=d['hits']['hits'][0]['source'];print({k:str(v)[:70] for k,v in h.items()});sys.exit()
if __name__=="__main__":
 for qs in sys.argv[1:]:
     d=q(qs);hits=d['hits']['hits'];print(f"== {qs}: {d['hits']['totalValue']} hits")
     for h in hits:
         s=h['source'];print(" ",s.get('wordmark'),"|",'LIVE' if s.get('alive') else 'dead',"|",s.get('internationalClass'),"|",(s.get('ownerName') or [''])[0] if isinstance(s.get('ownerName'),list) else s.get('ownerName'),"|",h['id'])
