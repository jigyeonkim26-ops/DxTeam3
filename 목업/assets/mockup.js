document.querySelectorAll('[data-toast]').forEach((element)=>element.addEventListener('click',(event)=>{event.preventDefault();const toast=document.querySelector('.toast');toast.textContent=element.dataset.toast;toast.classList.add('show');setTimeout(()=>toast.classList.remove('show'),2200)}));
document.querySelectorAll('form[data-demo]').forEach((form)=>form.addEventListener('submit',(event)=>{event.preventDefault();const toast=document.querySelector('.toast');toast.textContent=form.dataset.demo;toast.classList.add('show');setTimeout(()=>toast.classList.remove('show'),2200)}));

