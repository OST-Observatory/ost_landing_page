document.addEventListener('DOMContentLoaded', function () {
  const bannerContainer = document.getElementById('article-banner');
  if (!bannerContainer) {
    return;
  }

  let cachedArticles = null;
  let currentIndex = 0;
  let rotateTimer = null;

  function fetchArticles() {
    if (cachedArticles) {
      return Promise.resolve(cachedArticles);
    }

    return fetch('news_articles/articles.json')
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
        return response.json();
      })
      .then(articles => {
        articles.sort((a, b) => new Date(b.publication_date) - new Date(a.publication_date));
        cachedArticles = articles.slice(0, 5);
        return cachedArticles;
      });
  }

  function thumbnailPath(article) {
    return article.thumbnail_path || article.image_path;
  }

  function formatDate(publicationDate) {
    const dateComponents = publicationDate.split('-');
    return `${dateComponents[2]}.${dateComponents[1]}.${dateComponents[0]}`;
  }

  function navigateToArticle(filename) {
    window.location.href = 'news_articles/' + filename;
  }

  function rotateBanner(articles, index) {
    bannerContainer.replaceChildren();

    const article = articles[index];
    const articlePreview = document.createElement('div');
    articlePreview.className = 'article-preview';

    const imageContainer = document.createElement('div');
    imageContainer.className = 'image-container';

    const img = document.createElement('img');
    img.src = 'news_articles/' + thumbnailPath(article);
    img.alt = article.title;
    img.addEventListener('click', () => navigateToArticle(article.filename));
    imageContainer.appendChild(img);

    const overlay = document.createElement('div');
    overlay.className = 'overlay';

    const indexInfo = document.createElement('div');
    indexInfo.className = 'index-info';
    indexInfo.textContent = `${index + 1} | ${articles.length}`;
    overlay.appendChild(indexInfo);

    const prevButton = document.createElement('button');
    prevButton.type = 'button';
    prevButton.className = 'toggle-button';
    prevButton.setAttribute('aria-label', 'Previous article');
    prevButton.innerHTML = '&#9664;';
    prevButton.addEventListener('click', event => {
      event.stopPropagation();
      togglePreview(-1);
    });
    overlay.appendChild(prevButton);

    const nextButton = document.createElement('button');
    nextButton.type = 'button';
    nextButton.className = 'toggle-button';
    nextButton.setAttribute('aria-label', 'Next article');
    nextButton.innerHTML = '&#9654;';
    nextButton.addEventListener('click', event => {
      event.stopPropagation();
      togglePreview(1);
    });
    overlay.appendChild(nextButton);

    imageContainer.appendChild(overlay);
    articlePreview.appendChild(imageContainer);

    const articleInfo = document.createElement('div');
    articleInfo.className = 'article-info';
    articleInfo.addEventListener('click', () => navigateToArticle(article.filename));

    const paragraph = document.createElement('p');
    const strong = document.createElement('strong');
    strong.textContent = article.title;
    paragraph.appendChild(strong);

    if (article.subtitle) {
      paragraph.appendChild(document.createTextNode(': ' + article.subtitle));
    }

    paragraph.appendChild(document.createTextNode(' | ' + formatDate(article.publication_date)));
    articleInfo.appendChild(paragraph);
    articlePreview.appendChild(articleInfo);

    bannerContainer.appendChild(articlePreview);
  }

  function togglePreview(offset) {
    if (!cachedArticles || cachedArticles.length === 0) {
      return;
    }

    currentIndex = (currentIndex + offset + cachedArticles.length) % cachedArticles.length;
    rotateBanner(cachedArticles, currentIndex);
  }

  function initializeBanner() {
    fetchArticles()
      .then(articles => {
        if (!articles || articles.length === 0) {
          bannerContainer.style.display = 'none';
          return;
        }

        rotateBanner(articles, currentIndex);

        rotateTimer = setInterval(() => {
          currentIndex = (currentIndex + 1) % articles.length;
          rotateBanner(articles, currentIndex);
        }, 10000);
      })
      .catch(error => {
        console.error('Error fetching articles:', error);
        bannerContainer.style.display = 'none';
      });
  }

  initializeBanner();
});
