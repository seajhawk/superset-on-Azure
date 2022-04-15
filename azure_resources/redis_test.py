from rich import print

import redis


redisConnect = "eisuperset01.redis.cache.windows.net:6380,password=yrLnjF1NMz8rvDhvtgn6JJg29VZaQQ58zAzCaDpi4b8=,ssl=True,abortConnect=False"

REDIS_PORT = 6379

ssl=True if REDIS_PORT == 6380 else False

print(f"SSL: {ssl}")

r = redis.StrictRedis(host='eisuperset01.redis.cache.windows.net', port=REDIS_PORT, db=0, password='yrLnjF1NMz8rvDhvtgn6JJg29VZaQQ58zAzCaDpi4b8=', ssl=ssl)
r.set('foo', 'bar')

print(r.get('foo'))



print("Done!")