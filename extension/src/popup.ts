import { getSavedWords, toggleStar, unsaveWord } from './storage';

async function renderPopup() {
  const words = await getSavedWords();
  const list = document.getElementById('wordList')!;
  const stats = document.getElementById('stats')!;

  stats.textContent = `${words.length} saved words`;

  if (words.length === 0) {
    list.innerHTML = '<div class="empty">No saved words yet. Click words in subtitles to save them.</div>';
    return;
  }

  const grouped = new Map<string, typeof words>();
  words.forEach(w => {
    const key = `${w.source} / ${w.program}`;
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key)!.push(w);
  });

  list.innerHTML = '';
  grouped.forEach((items, group) => {
    const header = document.createElement('div');
    header.style.cssText = 'font-size:12px;color:#888;margin:8px 0 4px;';
    header.textContent = group;
    list.appendChild(header);

    items.forEach(w => {
      const item = document.createElement('div');
      item.className = 'word-item';
      item.innerHTML = `
        <div>
          <div class="word-text">${w.word}</div>
          <div class="word-context">${w.context}</div>
          <div class="word-meta">${w.date}</div>
        </div>
        <span class="star ${w.starred ? 'active' : ''}" data-word="${w.word}">&#9733;</span>
      `;
      list.appendChild(item);
    });
  });

  list.querySelectorAll('.star').forEach(star => {
    star.addEventListener('click', async (e) => {
      const word = (e.target as HTMLElement).dataset.word!;
      await toggleStar(word);
      renderPopup();
    });
  });
}

renderPopup();
