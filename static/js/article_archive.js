document.addEventListener('DOMContentLoaded', function () {
    fetch('articles.json')
      .then(response => response.json())
      .then(data => renderArticles(data))
      .catch(error => console.error('Error fetching articles:', error));
});

function renderArticles(articles) {
    const articleGrid = document.getElementById('articleGrid');

    articles.sort((a, b) => new Date(b.publicationDate) - new Date(a.publicationDate));
    articles.reverse();

    articles.forEach(article => {
      const articleElement = document.createElement('div');
      articleElement.classList.add('article');

      //  Add link to article page
      articleElement.setAttribute("onclick", "window.location.href = '" + article.filename + "'");

      const thumbnailElement = document.createElement('div');
      thumbnailElement.classList.add('thumbnail');
      thumbnailElement.innerHTML = `<img src="../${article.image_path}" alt="${article.title}">`;

      const contentElement = document.createElement('div');
      contentElement.classList.add('content');
      contentElement.innerHTML = `
        <div class="title">${article.title}</div>
        <div class="subtitle">${article.subtitle}</div>
        <div class="date">Published on ${formatDate(article.publication_date)}</div>
      `;

      articleElement.appendChild(thumbnailElement);
      articleElement.appendChild(contentElement);

      articleGrid.appendChild(articleElement);
    });
}

function formatDate(dateString) {
    const options = { year: 'numeric', month: 'long', day: 'numeric' };
    return new Date(dateString).toLocaleDateString(undefined, options);
}
