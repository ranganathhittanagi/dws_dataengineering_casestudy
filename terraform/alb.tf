# Application Load Balancer fronting the Airflow webserver.
#
# HTTP-only for now: no owned domain means no ACM public certificate. Access is
# restricted to the admin IP allowlist at the ALB security group, and Airflow's own
# login (basic auth/session) applies behind that. Adding a domain + ACM HTTPS listener
# is the documented follow-up.

resource "aws_lb" "airflow" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]
}

resource "aws_lb_target_group" "airflow_web" {
  name     = "${var.project_name}-web-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.pipeline.id

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_target_group_attachment" "airflow_web" {
  target_group_arn = aws_lb_target_group.airflow_web.arn
  target_id        = aws_instance.airflow_control.id
  port             = 8080
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.airflow.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.airflow_web.arn
  }
}
