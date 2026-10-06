import {test} from 'node:test';
import {strict as assert} from 'node:assert';
import {validateAccount} from '../lib/passwords';
test('credentials reject unsafe or ambiguous identifiers and overlong bcrypt inputs',()=>{
 for(const name of ['ABCD','a@b','aa','a b','<script>'])assert.throws(()=>validateAccount(name,'a long password'));
 assert.throws(()=>validateAccount('aidant.exemple','court'));
 assert.throws(()=>validateAccount('aidant.exemple','é'.repeat(37)));
 assert.doesNotThrow(()=>validateAccount('aidant.exemple','Une phrase personnelle 2026'));
});
