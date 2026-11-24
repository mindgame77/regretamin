// Sector colours for the share card. The same tables as COLORS in js/map.js and SUB_PARENT in js/company.js;
// tests/share_card.test.mjs fails when they drift apart.
export const COLORS = { 'Enterprise software': '#A9C4E8', 'Health': '#F2A7A0', 'Fintech': '#F3D98B', 'Hardware & Robotics': '#9FD4C3', 'Consumer': '#D9B5E0', 'Climate & Energy': '#BFDCA0', 'Bio': '#C59AC7', 'AI agents': '#8E9BE0', 'AI models': '#C4CCF2', 'Security': '#A8BDB5', 'Crypto': '#F7E6B5', 'Media & Gaming': '#F5C19A', 'Food & Agriculture': '#D5E0A3', 'Defense': '#B5B5BD', 'Space': '#9AA5D1', 'Mobility': '#9CC9D9', 'Education': '#EFC4D0', 'Developer tools': '#B9E0E6', 'Real estate': '#E6C9B0', 'Govtech': '#C2D6C8', 'Other': '#DADFDD' };
export const SUB_PARENT = {
  'AI infrastructure': 'AI models', 'Payments': 'Fintech', 'Insurtech': 'Fintech', 'Wealth': 'Fintech', 'Digital health': 'Health',
  'Medtech': 'Health', 'Wellness': 'Health', 'Biotech': 'Bio', 'Commerce': 'Consumer', 'Travel': 'Consumer', 'Sports': 'Consumer',
  'HR Tech': 'Enterprise software', 'Legal Tech': 'Enterprise software', 'Marketing': 'Enterprise software', 'Cloud & Data': 'Developer tools',
  'Cybersecurity': 'Security', 'Hardware': 'Hardware & Robotics', 'Robotics': 'Hardware & Robotics', 'Semiconductors': 'Hardware & Robotics',
  'Manufacturing': 'Hardware & Robotics', 'Materials': 'Hardware & Robotics', 'Deep tech': 'Hardware & Robotics', 'Telecom': 'Hardware & Robotics',
  'Logistics': 'Mobility', 'Construction': 'Real estate', 'Media': 'Media & Gaming', 'Gaming': 'Media & Gaming', 'Food': 'Food & Agriculture',
  'Agriculture': 'Food & Agriculture'
};
export const sectorColor = (name) => COLORS[SUB_PARENT[name] || name] || COLORS.Other;
