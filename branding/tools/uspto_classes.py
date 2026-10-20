import json,sys
from uspto_query import q
G={'IC 009','IC 028','IC 041','IC 016'}
for qs in sys.argv[1:]:
    d=q(qs,400);hits=d['hits']['hits'];print(f"== {qs}: {d['hits']['totalValue']} total; live in 9/16/28/41:")
    for h in hits:
        s=h['source']
        if s.get('alive') and G & set(s.get('internationalClass') or []):
            print("  ",s.get('wordmark'),"|",s.get('internationalClass'),"|",(s.get('ownerName') or [''])[0][:60],"|",s.get('statusDescription'),"| sn",h['id'])
