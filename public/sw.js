const CACHE='liens-shell-v2';
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(['offline.html','icon.svg'].map(path=>new URL(path,self.registration.scope).href)))));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{if(e.request.mode==='navigate')e.respondWith(fetch(e.request).catch(()=>caches.match(new URL('offline.html',self.registration.scope).href)));});
self.addEventListener('push',e=>{let data={title:'lien ohain',body:'Un rappel vous attend dans votre espace.'};try{data={...data,...e.data.json()}}catch{}e.waitUntil(self.registration.showNotification(data.title,{body:data.body,data:{url:self.registration.scope}}));});
self.addEventListener('notificationclick',e=>{e.notification.close();e.waitUntil(self.clients.matchAll({type:'window'}).then(w=>w.length?w[0].focus():self.clients.openWindow(self.registration.scope)));});
