const inviteToast=(message)=>{const toast=document.querySelector('.toast');toast.textContent=message;toast.classList.add('show');setTimeout(()=>toast.classList.remove('show'),2200)};
const code=()=>`YN-${Math.random().toString(36).slice(2,6).toUpperCase()}`;
document.querySelectorAll('[data-generate-code]').forEach((button)=>button.addEventListener('click',()=>{const value=code();document.querySelector('[data-code-value]').textContent=value;inviteToast(`초대 코드 ${value}를 만들었어요.`)}));
document.querySelectorAll('[data-generate-link]').forEach((button)=>button.addEventListener('click',()=>{const value=new URL(`join-group.html?code=${code()}`,window.location.href).href;document.querySelector('[data-link-value]').textContent=value;inviteToast('카카오톡으로 공유할 초대 링크를 만들었어요.') }));
document.querySelectorAll('[data-copy-invite]').forEach((button)=>button.addEventListener('click',()=>{const value=document.querySelector(button.dataset.copyInvite).textContent;navigator.clipboard?.writeText(value);inviteToast('초대 정보를 복사했어요. (목업)')}));

