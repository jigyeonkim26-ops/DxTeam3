const params=new URLSearchParams(window.location.search);const code=params.get('code')||'YN-2026';
document.querySelectorAll('[data-join-code]').forEach((item)=>item.textContent=code);
const join=document.querySelector('[data-join-group]');
if(join){join.addEventListener('click',()=>{join.hidden=true;document.querySelector('#joinSuccess').hidden=false;const toast=document.querySelector('.toast');toast.textContent='연남 산책단에 참여했어요.';toast.classList.add('show');setTimeout(()=>toast.classList.remove('show'),2200)})}

