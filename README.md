# Bài 4 — Docker Network và Named Volume

## Chuẩn bị

Build backend từ thư mục bài 3 trước. Script dùng image `hw-backend:multistage`, network `app-net`, volume `db-data`, database `appdb`, user `appuser`, và ánh xạ API ra cổng máy chủ 8081.

Đặt password DB qua biến môi trường để không lưu credential trong repository:

```bash
export POSTGRES_PASSWORD='your-local-db-password'
chmod +x commands.sh
./commands.sh
```

Script dừng nếu container tên `db-server` hoặc `app-container` đã tồn tại; hãy kiểm tra container đó trước khi xử lý. Network và volume được tái sử dụng nếu đã có. Cuối bài, hai container và volume vẫn được giữ lại để tiếp tục kiểm tra.

## Nội dung kiểm chứng tự động

Script tạo bridge network `app-net`, named volume `db-data`, khởi động PostgreSQL 15 Alpine và backend với `DB_HOST=db-server`. Nó kiểm tra DNS bằng `ping`, gọi health endpoint, ghi một bản ghi qua API, xóa rồi tạo lại riêng container PostgreSQL với cùng volume và đọc lại bản ghi.

Kết thúc thành công cần in `Persistence verification passed`. Có thể kiểm tra thêm:

```bash
docker network ls | grep app-net
docker volume ls | grep db-data
docker network inspect app-net
docker exec -it app-container ping -c 2 db-server
curl http://localhost:8081/api/records
```

Image/backend cần từ bài 3. Nếu muốn chạy lại từ đầu, trước tiên kiểm tra rồi xóa đúng các container của lần thực hành trước; không xóa volume `db-data` nếu cần giữ dữ liệu.
