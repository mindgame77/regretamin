// What can make a startup special in its field: [name, the question, what counts as proof, what does not count, about the founders?].
// Copied from the tab "Secret sauce" of the sheet "Regretamin: what investors check" (25 rows) on 26 Nov 2026.
// These only ever add: a deck with none of them loses nothing (founder, 26 Nov: "not for everyone ... wow, this is special").
export const SPECIAL = [
  ['The secret', "What is the super secret behind this startup's success?", 'One thing you can say in a sentence that explains why you win', '"Hard work", "great team", "passion"', false],
  ['Unfair insight', 'What do you know that others do not, or do not believe?', 'A specific finding from your own work that rivals have not acted on', 'A trend everyone reads about', true],
  ['Earned knowledge', 'What did you learn the hard way that a newcomer would need years to learn?', 'Years inside the industry, a failed first attempt, hundreds of customer calls', 'Reading reports', true],
  ['Exclusive data', 'What data do you have that nobody else can get?', 'A signed exclusive source, or data that only your product produces', 'Public data anyone can download', false],
  ['Exclusive access', 'What door is open to you and closed to others?', 'A signed supply deal, licence, partnership or channel', 'A meeting that went well', false],
  ['Distribution', 'How do you reach buyers cheaper than anyone else?', 'A channel you own or control, with numbers', '"We will do content"', false],
  ['Audience', 'Who is already listening to you?', 'A newsletter, community or following made of your buyers', 'A large following of the wrong people', true],
  ['Founder reputation', 'Do buyers or engineers already know the founders?', 'Known name in the field: talks, papers, open-source work, past company', 'A big title at a big company, unknown outside it', true],
  ['Storytelling', 'Can a founder hold a room?', 'Video, talks or podcasts where the story lands', 'A polished deck with nobody who can present it', true],
  ['Speed', 'Why are you faster than everyone else?', 'A record of shipping weekly; live while rivals announce', '"We move fast"', false],
  ['Technology', 'What can you build that others cannot?', 'A working result that others have tried and failed to match', 'A common tool, used well', false],
  ['Timing', 'What did you see first?', 'You started before the change everyone now sees, and can show the date', 'Starting the month it made the news', false],
  ['Virality', 'Why does it spread without you pushing?', 'Each use shows the product to someone new, and you measured it', 'A share button', false],
  ['Network effect', 'Why is it better with every user?', 'A number that improves as users join', '"We are a platform"', false],
  ['Community', 'Who would be upset if you shut down?', 'Users who answer each other and bring friends', 'A quiet chat group', false],
  ['Customer love', 'Do customers sell it for you?', 'Unprompted referrals, public praise, customers who invest', 'Polite testimonials you asked for', false],
  ['Cost edge', 'Why can you do it for less?', 'A real structural reason: team location, own supply, own technology', 'Paying yourselves nothing', false],
  ['Rule or licence', 'Is there a rule that helps you and blocks others?', 'A licence, approval or certification you hold and others must wait for', 'An application that is filed', false],
  ['Lock-in', 'Why is it hard to leave you?', "Customers' data, workflow or integrations sit inside the product", 'An annual contract', false],
  ['Talent magnet', 'Who joins you that would not join others?', 'Named people who left strong jobs to join', 'A long list of advisers', true],
  ['Backers', 'Who already believes in you?', 'A respected founder or operator in your field who put in their own money', 'A famous name on an adviser slide', false],
  ['University', 'Did a founder study or do research somewhere that keeps producing funded founders in this field?', 'A degree or research at a university known for this field, named on the team slide', 'A short course, an online certificate, or a famous name with an unrelated degree', true],
  ['Past employer', 'Did a founder work somewhere that taught exactly this?', 'Years in a senior or technical role at a company known in this field', 'An internship, or a famous logo with an unrelated job', true],
  ['Earlier company', 'Has a founder built a company before, and what happened to it?', 'A named company with its outcome: sold, raised money, or still running with customers', 'A project that never had users', true],
];
export const SPECIAL_BY = new Map(SPECIAL.map((r) => [r[0].toLowerCase(), r]));
