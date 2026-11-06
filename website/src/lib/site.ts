export const site = {
  name: 'Mantis',
  version: '0.2.2',
  repo: 'https://github.com/Caracolaracol/mantis',
  release: 'https://github.com/Caracolaracol/mantis/releases/latest',
  download: 'https://github.com/Caracolaracol/mantis/releases/download/v0.2.2/Mantis-0.2.2.dmg',
  checksum: 'https://github.com/Caracolaracol/mantis/releases/download/v0.2.2/Mantis-0.2.2.dmg.sha256',
  portfolio: 'https://agustinrojasm.vercel.app',
};

export function href(path = '') {
  return `${import.meta.env.BASE_URL.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;
}
