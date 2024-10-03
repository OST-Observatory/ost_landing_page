document.addEventListener("DOMContentLoaded", function() {
  function fetchArticles() {
    // Retrieve articles, sort by publication date, and get the 5 most recent.
    return fetch('news_articles/articles.json')
      .then(response => response.json())
      .then(articles => {
        articles.sort((a, b) => new Date(b.publication_date) - new Date(a.publication_date));
        return articles.slice(0, 5);
      })
      .catch(error => console.error('Error fetching articles:', error));
  }

  function rotateBanner(articles, bannerContainer, currentIndex) {
    // Remove the current article preview
    bannerContainer.innerHTML = '';

    // Add the next article preview
    const article = articles[currentIndex];
    const articlePreview = createArticlePreview(article, articles, bannerContainer, currentIndex);
    bannerContainer.appendChild(articlePreview);
  }

  function createArticlePreview(article, articles, bannerContainer, currentIndex) {
    const articlePreview = document.createElement('div');
    articlePreview.classList.add('article-preview');

    // Reformat the publication date to DD.MM.YYYY
    const dateComponents = article.publication_date.split('-');
    const formattedDate = `${dateComponents[2]}.${dateComponents[1]}.${dateComponents[0]}`;

    // Customize the structure and styles based on your needs
    articlePreview.innerHTML = `
      <div class="image-container">
        <img src="${article.image_path}" alt="${article.title}" onclick="window.location.href = 'news_articles/${article.filename}'">
        <div class="overlay">
          <div class="index-info">${currentIndex + 1} | ${articles.length}</div>
          <button class="toggle-button" onclick="togglePreview(-1, ${articles.length}, ${currentIndex}, '${bannerContainer.id}')">&#9664;</button>
          <button class="toggle-button" onclick="togglePreview(1, ${articles.length}, ${currentIndex}, '${bannerContainer.id}')">&#9654;</button>
        </div>
      </div>
      <div class="article-info" onclick="window.location.href = 'news_articles/${article.filename}'">
        <p>
          <strong>${article.title}</strong>${article.subtitle ? `: ${article.subtitle}` : ''} | ${formattedDate}
        </p>
      </div>
    `;

    return articlePreview;
  }

  window.togglePreview = async function(offset, totalArticles, currentIndex, bannerContainerId) {
    const newIndex = (currentIndex + offset + totalArticles) % totalArticles;
    const bannerContainer = document.getElementById(bannerContainerId);
    const articles = await fetchArticles(); // Wait for the articles to be fetched
    rotateBanner(articles, bannerContainer, newIndex);
  };

  function initializeBanner() {
    // Fetch articles and initialize the banner
    const bannerContainer = document.getElementById('article-banner');
    let currentIndex = 0;
    fetchArticles().then(articles => {
      rotateBanner(articles, bannerContainer, currentIndex);

      // Set up a timer to rotate the banner every few seconds
      setInterval(() => {
        // Increment the index, and loop back to the first article if necessary
        currentIndex = (currentIndex + 1) % articles.length;

        rotateBanner(articles, bannerContainer, currentIndex);
      }, 10000);  // Rotate every 10 seconds
    });
  }

  // Call the initialization function
  initializeBanner();
});
