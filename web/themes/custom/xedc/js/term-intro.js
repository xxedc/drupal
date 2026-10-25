document.addEventListener('DOMContentLoaded',function(){
  document.querySelectorAll('.term-intro').forEach(function(w){
    var t=w.querySelector('.term-intro__text'),b=w.querySelector('.term-intro__toggle');
    if(!t||!b)return;
    if(t.scrollHeight<=t.clientHeight+2){b.hidden=true;return;}
    b.addEventListener('click',function(){
      var o=w.classList.toggle('is-open');
      b.textContent=o?'收起':'展开';
      b.setAttribute('aria-expanded',o);
    });
  });
});
