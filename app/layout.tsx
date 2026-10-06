import type { Metadata, Viewport } from 'next';
import './globals.css';
import {appPath} from '@/lib/paths';
export const metadata:Metadata={title:'lien ohain',description:'Un espace partagé pour organiser les visites, consulter les horaires et partager les nouvelles en famille.',manifest:appPath('/manifest.webmanifest'),appleWebApp:{capable:true,title:'lien ohain',statusBarStyle:'default'},icons:{icon:appPath('/icon.svg'),apple:appPath('/icon.svg')}};
export const viewport:Viewport={width:'device-width',initialScale:1,themeColor:'#365b86'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="fr"><body>{children}</body></html>}
