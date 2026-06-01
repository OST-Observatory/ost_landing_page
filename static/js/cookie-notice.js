(function () {
  const STORAGE_KEY = 'ost_cookie_notice_ack';
  const LEARN_MORE_URL = 'https://en.wikipedia.org/wiki/HTTP_cookie';

  const MESSAGE =
    'This website only uses essential cookies that are required for it to work properly. ' +
    'They are not used for tracking or advertising.';

  function acknowledgeNotice(bar) {
    try {
      localStorage.setItem(STORAGE_KEY, '1');
    } catch (error) {
      console.warn('Could not save cookie notice preference:', error);
    }
    bar.remove();
  }

  function createNoticeBar() {
    const bar = document.createElement('div');
    bar.className = 'cookie-notice';
    bar.setAttribute('role', 'region');
    bar.setAttribute('aria-label', 'Cookie notice');

    const text = document.createElement('p');
    text.className = 'cookie-notice__text';
    text.textContent = MESSAGE;

    const actions = document.createElement('div');
    actions.className = 'cookie-notice__actions';

    const learnMore = document.createElement('a');
    learnMore.className = 'cookie-notice__link';
    learnMore.href = LEARN_MORE_URL;
    learnMore.textContent = 'Learn more';
    learnMore.rel = 'noopener noreferrer';
    learnMore.target = '_blank';

    const okButton = document.createElement('button');
    okButton.type = 'button';
    okButton.className = 'cookie-notice__button';
    okButton.textContent = 'OK';
    okButton.addEventListener('click', () => acknowledgeNotice(bar));

    actions.appendChild(learnMore);
    actions.appendChild(okButton);
    bar.appendChild(text);
    bar.appendChild(actions);

    document.body.appendChild(bar);
    okButton.focus();
  }

  document.addEventListener('DOMContentLoaded', function () {
    try {
      if (localStorage.getItem(STORAGE_KEY)) {
        return;
      }
    } catch (error) {
      console.warn('Could not read cookie notice preference:', error);
    }
    createNoticeBar();
  });
})();
