export const site = {
  name: 'Mantis',
  version: '0.4.0',
  repo: 'https://github.com/Caracolaracol/mantis',
  release: 'https://github.com/Caracolaracol/mantis/releases/latest',
  download: 'https://github.com/Caracolaracol/mantis/releases/download/v0.4.0/Mantis-0.4.0.dmg',
  checksum: 'https://github.com/Caracolaracol/mantis/releases/download/v0.4.0/Mantis-0.4.0.dmg.sha256',
  sonomaRelease: 'https://github.com/Caracolaracol/mantis/releases/tag/v0.4.2-sonoma',
  sonomaVersion: '0.4.2',
  sonomaDownload: 'https://github.com/Caracolaracol/mantis/releases/download/v0.4.2-sonoma/Mantis-0.4.2-macOS14.dmg',
  portfolio: 'https://agustinrojasm.vercel.app',
};

export function href(path = '') {
  return `${import.meta.env.BASE_URL.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;
}

export type Language = 'en' | 'es';
export type Section = 'home' | 'docs' | 'license';
export function localizedHref(language: Language, section: Section = 'home') {
  const routes = {
    en: { home: '', docs: 'documentation/', license: 'license/' },
    es: { home: 'es/', docs: 'documentacion/', license: 'licencia/' },
  };
  return href(routes[language][section]);
}
