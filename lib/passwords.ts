export function validateAccount(username:string,password:string){
 if(!/^[a-z0-9._-]{3,40}$/.test(username))throw Error('Identifiant : 3 à 40 lettres minuscules, chiffres, points, tirets ou traits de soulignement.');
 if(password.length<10||new TextEncoder().encode(password).length>72)throw Error('Choisissez un mot de passe de 10 caractères minimum et 72 octets maximum.');
}
