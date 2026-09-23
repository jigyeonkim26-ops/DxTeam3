const preview=document.querySelector('#photoPreview');
const empty=document.querySelector('#cameraEmpty');
const showPhoto=(file)=>{if(!file)return;preview.src=URL.createObjectURL(file);preview.hidden=false;empty.hidden=true};
document.querySelectorAll('[data-camera-input]').forEach((input)=>input.addEventListener('change',()=>showPhoto(input.files[0])));

