import type {CareState} from './domain';
export const contentKeys=['medications','consultations','symptoms','messages','visits'] as const;
export function visibleFamily(base:CareState,showExamples:boolean):CareState{
 const result={...base};for(const key of contentKeys){const real=base[key].filter(r=>!r.example);const sample=showExamples?(base.examples?.[key]||[]).map(r=>({...r,example:true})):[];(result[key] as unknown[])=key==='visits'?[...real,...sample.filter(s=>!real.some(r=>'date' in r&&r.date===('date' in s?s.date:'')))].sort((a,b)=>('date' in a?a.date:'').localeCompare('date' in b?b.date:'')):[...real,...sample]}return result;
}
